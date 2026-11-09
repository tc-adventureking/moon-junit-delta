///|
pub struct DiffConfig {
  slowdown_pct : Int32
  slowdown_floor_us : Int64
  fail_on : ReadOnlyArray[String]
}

///|
pub struct DiffEntry {
  priv scope : Int32
  priv encoded_name : String
  id : TestId
  category : String
  before : TestCase?
  after : TestCase?
  baseline_time_us : Int64?
  slowdown : Bool
  known_flaky : Bool
}

///|
pub struct DiffResult {
  priv scopes : ReadOnlyArray[Scope]
  entries : ReadOnlyArray[DiffEntry]
  diagnostics : ReadOnlyArray[Diagnostic]
  violations : ReadOnlyArray[String]
  baseline_count : Int32
  candidate_count : Int32
  history_count : Int32
}

///|
pub fn default_config() -> DiffConfig {
  {
    slowdown_pct: 50,
    slowdown_floor_us: 200000L,
    fail_on: ["new_failure", "added_failing", "removed", "empty_report"],
  }
}

///|
pub fn diff_config(
  slowdown_pct~ : Int32 = 50,
  slowdown_floor_us~ : Int64 = 200000L,
  fail_on~ : Array[String] = [
    "new_failure", "added_failing", "removed", "empty_report",
  ],
) -> DiffConfig raise InputError {
  if slowdown_pct < 0 || slowdown_pct > 1000000 {
    raise InvalidInput("slowdown percentage must be 0..1000000")
  }
  if slowdown_floor_us < 0L || slowdown_floor_us > 9000000000000L {
    raise InvalidInput("slowdown floor must be 0..9000000000000 microseconds")
  }
  let valid = [
    "new_failure", "added_failing", "still_failing", "removed", "newly_skipped",
    "flaky", "slowdown", "empty_report",
  ]
  for key in fail_on {
    if !valid.contains(key) {
      raise InvalidInput("unknown gate: \{key}")
    }
  }
  {
    slowdown_pct,
    slowdown_floor_us,
    fail_on: ReadOnlyArray::from_array(fail_on),
  }
}

///|
fn is_failure(outcome : Outcome) -> Bool {
  outcome == Failed || outcome == Errored
}

///|
/// Final outcomes drive categories. Flakiness is an independent annotation.
pub fn classify(before : Outcome?, after : Outcome?) -> String {
  match (before, after) {
    (None, None) => "absent"
    (Some(_), None) => "removed"
    (None, Some(Failed | Errored)) => "added_failing"
    (None, Some(_)) => "added"
    (Some(Failed | Errored), Some(Passed)) => "fixed"
    (Some(Failed | Errored), Some(Failed | Errored)) => "still_failing"
    (Some(_), Some(Failed | Errored)) => "new_failure"
    (Some(Skipped), Some(Passed)) => "unskipped"
    (Some(Skipped), Some(Skipped)) => "unchanged"
    (Some(_), Some(Skipped)) => "newly_skipped"
    _ => "unchanged"
  }
}

///|
fn report_index(
  report : Report,
  pool : ScopePool,
) -> Map[(Int32, String), TestCase] raise InputError {
  let index : Map[(Int32, String), TestCase] = Map([])
  if report.cases.length() > 100000 {
    raise Rejected("limit_exceeded", "report exceeds 100000 testcases")
  }
  let mapping = pool.remap(report.scopes)
  for item in report.cases {
    let key = (mapping[item.scope], item.name)
    if index.contains(key) {
      raise Rejected(
        "duplicate_test_id",
        "duplicate test ID in report: \{item.id.preview()}",
      )
    }
    if item.time_us is Some(t) && (t < 0L || t > 9000000000000L) {
      raise Rejected("invalid_time", "time out of supported bounds")
    }
    index[key] = item
  }
  index
}

///|
priv struct HistoricalStats {
  times : Array[Int64]
  mut seen_pass : Bool
  mut seen_fail : Bool
  mut known_flaky : Bool
}

///|
/// Inputs are chronological runs; file merging is a separate explicit operation.
pub fn compare(
  history : Array[Report],
  candidate : Report,
  config~ : DiffConfig = default_config(),
) -> DiffResult raise InputError {
  if history.is_empty() || history.length() > 50 {
    raise InvalidInput("provide 1..50 baseline runs")
  }
  let cfg = diff_config(
    slowdown_pct=config.slowdown_pct,
    slowdown_floor_us=config.slowdown_floor_us,
    fail_on=config.fail_on.iter().to_array(),
  )
  let pool = new_scope_pool()
  let base = report_index(history[history.length() - 1], pool)
  let head = report_index(candidate, pool)
  let keys : Map[(Int32, String), Bool] = Map([])
  for key, _ in base {
    keys[key] = true
  }
  for key, _ in head {
    keys[key] = true
  }
  let stats : Map[(Int32, String), HistoricalStats] = Map([])
  for i = 0; i < history.length(); i = i + 1 {
    let index = if i == history.length() - 1 {
      base
    } else {
      report_index(history[i], pool)
    }
    for key, item in index {
      if !keys.contains(key) {
        continue
      }
      let stat = match stats.get(key) {
        Some(stat) => stat
        None => {
          let stat : HistoricalStats = {
            times: [],
            seen_pass: false,
            seen_fail: false,
            known_flaky: false,
          }
          stats[key] = stat
          stat
        }
      }
      stat.seen_pass = stat.seen_pass || item.outcome == Passed
      stat.seen_fail = stat.seen_fail || is_failure(item.outcome)
      stat.known_flaky = stat.known_flaky || item.flaky
      if item.outcome == Passed && item.time_us is Some(time) {
        stat.times.push(time)
      }
    }
  }
  let entries : Array[DiffEntry] = []
  for key, _ in keys {
    let before = base.get(key)
    let after = head.get(key)
    let id = match (before, after) {
      (_, Some(item)) | (Some(item), None) => item.id
      _ => continue
    }
    let category = classify(
      before.map(x => x.outcome),
      after.map(x => x.outcome),
    )
    let (baseline_time_us, known_flaky) = match stats.get(key) {
      None => (None, false)
      Some(stat) => {
        stat.times.sort()
        let median = if stat.times.is_empty() {
          None
        } else {
          Some(stat.times[(stat.times.length() - 1) / 2])
        }
        (median, stat.known_flaky || (stat.seen_pass && stat.seen_fail))
      }
    }
    let slowdown = match (before, after, baseline_time_us) {
      (Some(b), Some(c), Some(t)) if b.outcome == Passed && c.outcome == Passed =>
        match c.time_us {
          Some(u) =>
            u * 100L > t * (100L + cfg.slowdown_pct.to_int64()) &&
            u - t >= cfg.slowdown_floor_us
          None => false
        }
      _ => false
    }
    entries.push({
      id,
      category,
      before,
      after,
      baseline_time_us,
      slowdown,
      known_flaky,
      scope: key.0,
      encoded_name: Json(key.1).stringify(),
    })
  }
  let ranks = pool.ranks()
  entries.sort_by((a, b) => {
    let category = a.category.lexical_compare(b.category)
    if category != 0 {
      return category
    }
    let scope = ranks[a.scope].compare(ranks[b.scope])
    if scope != 0 {
      scope
    } else {
      a.encoded_name.lexical_compare(b.encoded_name)
    }
  })
  let diagnostics : Array[Diagnostic] = []
  for report in history {
    for d in report.diagnostics {
      diagnostics.push(d)
    }
  }
  for d in candidate.diagnostics {
    diagnostics.push(d)
  }
  let violations : Array[String] = []
  for gate in cfg.fail_on {
    let hit = if gate == "empty_report" {
      candidate.cases.is_empty()
    } else {
      entries.any(e => {
        match gate {
          "flaky" => e.after.map(x => x.flaky).unwrap_or(false)
          "slowdown" => e.slowdown
          _ => e.category == gate
        }
      })
    }
    if hit && !violations.contains(gate) {
      violations.push(gate)
    }
  }
  violations.sort_by((a, b) => a.lexical_compare(b))
  {
    scopes: ReadOnlyArray::from_array(pool.scopes),
    entries: ReadOnlyArray::from_array(entries),
    diagnostics: ReadOnlyArray::from_array(diagnostics),
    violations: ReadOnlyArray::from_array(violations),
    baseline_count: base.length(),
    candidate_count: head.length(),
    history_count: history.length(),
  }
}

///|
pub fn DiffResult::exit_code(self : DiffResult) -> Int32 {
  if self.violations.is_empty() {
    0
  } else {
    1
  }
}
