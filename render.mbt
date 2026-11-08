///|
/// Times are bounded below 2^53, so JSON numbers preserve every microsecond.
fn time_json(time : Int64?) -> Json {
  match time {
    Some(value) => Json::number(value.to_double())
    None => Json::null()
  }
}

///|
fn case_json(case_ : TestCase?) -> Json {
  match case_ {
    None => Json::null()
    Some(c) =>
      {
        "outcome": Json(c.outcome.label()),
        "attempts": Json(c.attempts),
        "flaky": Json(c.flaky),
        "time_us": time_json(c.time_us),
        "message": Json(c.message),
        "source": Json(c.source),
      }
  }
}

///|
pub fn Report::to_json(self : Report) -> Json {
  {
    "cases": Json(
      self.cases.map(c => {
        "id": c.id.to_json(),
        "name": Json(c.name),
        "classname": match c.classname {
          Some(s) => Json(s)
          None => Json::null()
        },
        "is_passed": Json(c.is_passed()),
        "is_failure": Json(c.is_failure()),
        "is_error": Json(c.is_error()),
        "is_skipped": Json(c.is_skipped()),
        "is_flaky": Json(c.is_flaky()),
        "is_rerun": Json(c.is_rerun()),
        "final_results": Json(c.final_results),
        "interim_results": Json(c.interim_results),
        "result": case_json(Some(c)),
      }),
    ),
    "diagnostics": Json(
      self.diagnostics.map(d => {
        "source": Json(d.source),
        "code": Json(d.code),
        "message": Json(d.message),
      }),
    ),
  }
}

///|
pub fn DiffResult::to_json(self : DiffResult) -> Json {
  let counts : Map[String, Int32] = Map([])
  for item in self.entries {
    counts[item.category] = counts.get(item.category).unwrap_or(0) + 1
  }
  {
    "schema_version": 1,
    "baseline_count": Json(self.baseline_count),
    "candidate_count": Json(self.candidate_count),
    "history_count": Json(self.history_count),
    "counts": Json(counts),
    "gate": {
      "passed": Json(self.violations.is_empty()),
      "violations": Json(self.violations),
      "exit_code": Json(self.exit_code()),
    },
    "entries": Json(
      self.entries.map(e => {
        "id": e.id.to_json(),
        "category": Json(e.category),
        "before": case_json(e.before),
        "after": case_json(e.after),
        "baseline_time_us": time_json(e.baseline_time_us),
        "slowdown": Json(e.slowdown),
        "known_flaky": Json(e.known_flaky),
      }),
    ),
    "diagnostics": Json(
      self.diagnostics.map(d => {
        "source": Json(d.source),
        "code": Json(d.code),
        "message": Json(d.message),
      }),
    ),
  }
}

///|
pub fn DiffResult::to_json_string(self : DiffResult) -> String {
  self.to_json().stringify()
}

///|
/// Render untrusted fields as plain text: no HTML, links or Markdown control syntax.
fn safe_cell(text : String) -> String {
  let builder = StringBuilder()
  for ch in text {
    match ch {
      '&' => builder.write_string("&amp;")
      '<' => builder.write_string("&lt;")
      '>' => builder.write_string("&gt;")
      '|' => builder.write_string("&#124;")
      '`' => builder.write_string("&#96;")
      '[' => builder.write_string("&#91;")
      ']' => builder.write_string("&#93;")
      '*' => builder.write_string("&#42;")
      '_' => builder.write_string("&#95;")
      '\\' => builder.write_string("&#92;")
      '\n' | '\r' | '\t' => builder.write_string(" ")
      _ => if ch.to_int() >= 32 && ch.to_int() != 127 { builder.write_char(ch) }
    }
  }
  builder.to_string()
}

///|
fn entry_note(entry : DiffEntry) -> String {
  let notes : Array[String] = []
  if entry.after.map(c => c.flaky).unwrap_or(false) {
    notes.push("flaky attempts")
  }
  if entry.known_flaky {
    notes.push("historically inconsistent")
  }
  if entry.slowdown {
    notes.push("duration increase")
  }
  notes.join(", ")
}

///|
pub fn DiffResult::to_markdown(
  self : DiffResult,
  limit~ : Int32 = 50,
) -> String {
  let builder = StringBuilder()
  builder.write_string("# JUnit Delta\n\n")
  let gate = if self.violations.is_empty() { "PASS" } else { "FAIL" }
  builder.write_string(
    "Gate: **\{gate}**. Baseline: \{self.baseline_count}; candidate: \{self.candidate_count}; history runs: \{self.history_count}.\n\n",
  )
  if !self.violations.is_empty() {
    builder.write_string("Triggered: \{self.violations.join(", ")}.\n\n")
  }
  builder.write_string(
    "| Change | Test ID | Notes | Message |\n| --- | --- | --- | --- |\n",
  )
  let mut shown = 0
  for entry in self.entries {
    if entry.category == "unchanged" &&
      !entry.slowdown &&
      !entry.after.map(c => c.flaky).unwrap_or(false) {
      continue
    }
    if shown >= limit {
      continue
    }
    shown = shown + 1
    let message = entry.after.map(c => c.message).unwrap_or("")
    let short = if message.length() > 240 {
      message[:240].to_owned() + "…"
    } else {
      message
    }
    builder.write_string(
      "| \{entry.category} | \{safe_cell(entry.id.key())} | \{safe_cell(entry_note(entry))} | \{safe_cell(short)} |\n",
    )
  }
  builder.write_string(
    "\nShown \{shown} details (limit \{limit}); complete entries are available in JSON.\n",
  )
  if !self.diagnostics.is_empty() {
    builder.write_string("\nDiagnostics: \{self.diagnostics.length()}.\n")
    for i = 0; i < self.diagnostics.length() && i < 10; i = i + 1 {
      let d = self.diagnostics[i]
      builder.write_string(
        "- \{safe_cell(d.source)}: \{safe_cell(d.code)} — \{safe_cell(d.message)}\n",
      )
    }
  }
  builder.to_string()
}

///|
pub fn DiffResult::to_text(self : DiffResult) -> String {
  let builder = StringBuilder()
  let gate = if self.violations.is_empty() { "PASS" } else { "FAIL" }
  builder.write_string(
    "JUnit Delta: \{gate}\nBaseline \{self.baseline_count}, candidate \{self.candidate_count}, history \{self.history_count}\n",
  )
  for entry in self.entries {
    if entry.category != "unchanged" ||
      entry.slowdown ||
      entry.after.map(c => c.flaky).unwrap_or(false) {
      // JSON encodes control characters rather than emitting terminal escapes.
      builder.write_string(
        "\{entry.category}\t\{entry.id.key()}\t\{entry_note(entry)}\n",
      )
    }
  }
  if !self.violations.is_empty() {
    builder.write_string("Triggered: \{self.violations.join(", ")}\n")
  }
  builder.write_string("Diagnostics: \{self.diagnostics.length()}\n")
  builder.to_string()
}
