///|
/// Times are bounded below 2^53, so JSON numbers preserve every microsecond.
fn time_json(time : Int64?) -> Json {
  match time {
    Some(value) => Json::number(value.to_double())
    None => Json::null()
  }
}

///|
fn case_json(case_ : TestCase?, omit_source~ : Bool = false) -> Json {
  match case_ {
    None => Json::null()
    Some(c) =>
      {
        "outcome": Json(c.outcome.label()),
        "attempts": Json(c.attempts),
        "flaky": Json(c.flaky),
        "time_us": time_json(c.time_us),
        "message": Json(c.message),
        "source": Json(if omit_source { "" } else { c.source }),
      }
  }
}

///|
fn source_extra(case_ : TestCase?) -> Int64 {
  case_.map(c => c.source_units - 2L).unwrap_or(0L)
}

///|
fn diagnostic_json(d : Diagnostic) -> Json {
  { "source": Json(d.source), "code": Json(d.code), "message": Json(d.message) }
}

///|
fn report_case_json(c : TestCase, measure~ : Bool = false) -> Json {
  {
    "id": if measure {
      Json::null()
    } else {
      c.id.to_json()
    },
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
    "result": case_json(Some(c), omit_source=measure),
  }
}

///|
fn diff_entry_json(e : DiffEntry, measure~ : Bool = false) -> Json {
  {
    "id": if measure {
      Json::null()
    } else {
      e.id.to_json()
    },
    "category": Json(e.category),
    "before": case_json(e.before, omit_source=measure),
    "after": case_json(e.after, omit_source=measure),
    "baseline_time_us": time_json(e.baseline_time_us),
    "slowdown": Json(e.slowdown),
    "known_flaky": Json(e.known_flaky),
  }
}

///|
pub fn Report::to_json(
  self : Report,
  max_units~ : Int64 = 100000000L,
) -> Json raise InputError {
  let budget = output_budget(max_units)
  budget.add(json_units({ "cases": [], "diagnostics": [] }))
  for i = 0; i < self.cases.length(); i = i + 1 {
    let c = self.cases[i]
    let id_size = self.scopes[c.scope].id_units(Json(c.name).stringify(), 0)
    budget.add(
      json_units(report_case_json(c, measure=true)) +
      id_size -
      4L +
      source_extra(Some(c)) +
      (if i > 0 { 1L } else { 0L }),
    )
  }
  for i = 0; i < self.diagnostics.length(); i = i + 1 {
    budget.add(
      json_units(diagnostic_json(self.diagnostics[i])) +
      (if i > 0 { 1L } else { 0L }),
    )
  }
  {
    "cases": Json(self.cases.map(c => report_case_json(c))),
    "diagnostics": Json(self.diagnostics.map(d => diagnostic_json(d))),
  }
}

///|
pub fn DiffResult::to_json(
  self : DiffResult,
  max_units~ : Int64 = 100000000L,
) -> Json raise InputError {
  let counts : Map[String, Int32] = Map([])
  for item in self.entries {
    counts[item.category] = counts.get(item.category).unwrap_or(0) + 1
  }
  let header : Json = {
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
    "entries": [],
    "diagnostics": [],
  }
  let budget = output_budget(max_units)
  budget.add(json_units(header))
  for i = 0; i < self.entries.length(); i = i + 1 {
    let e = self.entries[i]
    budget.add(
      json_units(diff_entry_json(e, measure=true)) +
      self.scopes[e.scope].id_units(e.encoded_name, 0) -
      4L +
      source_extra(e.before) +
      source_extra(e.after) +
      (if i > 0 { 1L } else { 0L }),
    )
  }
  for i = 0; i < self.diagnostics.length(); i = i + 1 {
    budget.add(
      json_units(diagnostic_json(self.diagnostics[i])) +
      (if i > 0 { 1L } else { 0L }),
    )
  }
  guard header is Object(fields) else {
    raise InvalidInput("invalid output state")
  }
  fields["entries"] = Json(self.entries.map(e => diff_entry_json(e)))
  fields["diagnostics"] = Json(self.diagnostics.map(d => diagnostic_json(d)))
  header
}

///|
pub fn DiffResult::to_json_string(
  self : DiffResult,
  max_units~ : Int64 = 100000000L,
) -> String raise InputError {
  self.to_json(max_units~).stringify()
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
      '$' => builder.write_string("&#36;")
      '~' => builder.write_string("&#126;")
      '\\' => builder.write_string("&#92;")
      '\n' | '\r' | '\t' => builder.write_string(" ")
      _ =>
        if ch.to_int() >= 32 && (ch.to_int() < 127 || ch.to_int() > 159) {
          builder.write_char(ch)
        }
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
fn entry_has_detail(entry : DiffEntry) -> Bool {
  entry.category != "unchanged" ||
  entry.slowdown ||
  entry.known_flaky ||
  entry.after.map(c => c.flaky).unwrap_or(false)
}

///|
pub fn DiffResult::to_markdown(
  self : DiffResult,
  limit~ : Int32 = 50,
  max_units~ : Int64 = 100000000L,
) -> String raise InputError {
  if limit < 0 {
    raise InvalidInput("detail limit cannot be negative")
  }
  let budget = output_budget(max_units)
  let builder = StringBuilder()
  let gate = if self.violations.is_empty() { "PASS" } else { "FAIL" }
  budget.write(
    builder,
    "# JUnit Delta\n\nGate: **\{gate}**. Baseline: \{self.baseline_count}; candidate: \{self.candidate_count}; history runs: \{self.history_count}.\n\n",
  )
  if !self.violations.is_empty() {
    budget.write(builder, "Triggered: \{self.violations.join(", ")}.\n\n")
  }
  budget.write(
    builder, "| Change | Test ID | Notes | Message |\n| --- | --- | --- | --- |\n",
  )
  let mut shown = 0
  for entry in self.entries {
    if !entry_has_detail(entry) || shown >= limit {
      continue
    }
    shown = shown + 1
    let message = entry.after.map(c => c.message).unwrap_or("")
    let short = if message.length() > 240 {
      truncate_utf16(message, 240) + "…"
    } else {
      message
    }
    let prefix = "| \{entry.category} | "
    let suffix = " | \{safe_cell(entry_note(entry))} | \{safe_cell(short)} |\n"
    budget.add(
      prefix.length().to_int64() +
      self.scopes[entry.scope].id_units(entry.encoded_name, 1) +
      suffix.length().to_int64(),
    )
    builder.write_string(prefix + safe_cell(entry.id.key()) + suffix)
  }
  budget.write(
    builder,
    "\nShown \{shown} details (limit \{limit}); complete entries are available in JSON.\n",
  )
  if !self.diagnostics.is_empty() {
    budget.write(builder, "\nDiagnostics: \{self.diagnostics.length()}.\n")
    for i = 0; i < self.diagnostics.length() && i < 10; i = i + 1 {
      let d = self.diagnostics[i]
      budget.add(
        8L + safe_units(d.source) + safe_units(d.code) + safe_units(d.message),
      )
      builder.write_string(
        "- \{safe_cell(d.source)}: \{safe_cell(d.code)} — \{safe_cell(d.message)}\n",
      )
    }
  }
  builder.to_string()
}

///|
pub fn DiffResult::to_text(
  self : DiffResult,
  max_units~ : Int64 = 100000000L,
) -> String raise InputError {
  let budget = output_budget(max_units)
  let builder = StringBuilder()
  let gate = if self.violations.is_empty() { "PASS" } else { "FAIL" }
  budget.write(
    builder,
    "JUnit Delta: \{gate}\nBaseline \{self.baseline_count}, candidate \{self.candidate_count}, history \{self.history_count}\n",
  )
  for entry in self.entries {
    if entry_has_detail(entry) {
      let note = entry_note(entry)
      budget.add(
        self.scopes[entry.scope].id_units(entry.encoded_name, 2) +
        entry.category.length().to_int64() +
        note.length().to_int64() +
        3L,
      )
      builder.write_string(
        "\{entry.category}\t\{terminal_text(entry.id.key())}\t\{note}\n",
      )
    }
  }
  if !self.violations.is_empty() {
    budget.write(builder, "Triggered: \{self.violations.join(", ")}\n")
  }
  budget.write(builder, "Diagnostics: \{self.diagnostics.length()}\n")
  builder.to_string()
}

///|
fn OutputBudget::write(
  self : OutputBudget,
  builder : StringBuilder,
  text : String,
) -> Unit raise InputError {
  self.add(text.length().to_int64())
  builder.write_string(text)
}
