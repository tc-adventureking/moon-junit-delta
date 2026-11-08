///|
pub struct DiffConfig {
  slowdown_pct : Int32
  slowdown_floor_us : Int64
  fail_on : Array[String]
}

///|
pub struct DiffEntry {
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
  entries : Array[DiffEntry]
  diagnostics : Array[Diagnostic]
  violations : Array[String]
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
  { slowdown_pct, slowdown_floor_us, fail_on: fail_on.copy(), }
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
fn report_index(report : Report) -> Map[String, TestCase] raise InputError {
  let index : Map[String, TestCase] = Map([])
  if report.cases.length() > 100000 {
    raise InvalidInput("report exceeds 100000 testcases")
  }
  for item in report.cases {
    let key = item.id.key()
    if index.contains(key) {
      raise InvalidInput("duplicate test ID in report: \{key}")
    }
    if item.time_us is Some(t) && (t < 0L || t > 9000000000000L) {
      raise InvalidInput("time out of supported bounds")
    }
    index[key] = item
  }
  index
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
    fail_on=config.fail_on,
  )
  let indexes = history.map(report_index)
  let base = indexes[indexes.length() - 1]
  let head = report_index(candidate)
  let keys : Map[String, Bool] = Map([])
  for key, _ in base {
    keys[key] = true
  }
  for key, _ in head {
    keys[key] = true
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
    let times : Array[Int64] = []
    let mut seen_pass = false
    let mut seen_fail = false
    let mut known_flaky = false
    for idx in indexes {
      if idx.get(key) is Some(item) {
        if item.outcome == Passed {
          seen_pass = true
        }
        if is_failure(item.outcome) {
          seen_fail = true
        }
        known_flaky = known_flaky || item.flaky
        if item.outcome == Passed && item.time_us is Some(t) {
          times.push(t)
        }
      }
    }
    known_flaky = known_flaky || (seen_pass && seen_fail)
    times.sort()
    let baseline_time_us = if times.is_empty() {
      None
    } else {
      Some(times[(times.length() - 1) / 2])
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
    })
  }
  entries.sort_by((a, b) => {
    let first = a.category.lexical_compare(b.category)
    if first != 0 {
      first
    } else {
      a.id.key().lexical_compare(b.id.key())
    }
  })
  let diagnostics : Array[Diagnostic] = []
  for report in history {
    diagnostics.append(report.diagnostics)
  }
  diagnostics.append(candidate.diagnostics)
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
    entries,
    diagnostics,
    violations,
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
