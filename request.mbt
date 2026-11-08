///|
fn field(value : Json, key : String) -> Json? raise InputError {
  match value {
    Object(m) => m.get(key)
    _ => raise InvalidInput("expected an object")
  }
}

///|
fn string_field(
  value : Json,
  key : String,
  default : String,
) -> String raise InputError {
  match field(value, key) {
    None => default
    Some(String(s)) => s
    _ => raise InvalidInput("\{key} must be a string")
  }
}

///|
fn integer_field(
  value : Json,
  key : String,
  default : Int64,
  maximum : Int64,
) -> Int64 raise InputError {
  match field(value, key) {
    None => default
    Some(Number(n, ..)) if n >= 0.0 && n <= maximum.to_double() => {
      let i = n.to_int64()
      if i.to_double() != n {
        raise InvalidInput("\{key} must be an integer")
      }
      i
    }
    _ => raise InvalidInput("\{key} must be an integer in 0..\{maximum}")
  }
}

///|
fn parse_duplicates(value : String) -> DuplicatePolicy raise InputError {
  match value {
    "error" => Reject
    "attempts" => Attempts
    _ => raise InvalidInput("duplicates must be error or attempts")
  }
}

///|
fn input_document(
  value : Json,
  duplicates : DuplicatePolicy,
) -> Report raise InputError {
  let source = string_field(value, "source", "<input>")
  let xml = string_field(value, "xml", "")
  parse_report(xml, source~, duplicates~)
}

///|
fn input_run(
  value : Json,
  duplicates : DuplicatePolicy,
) -> Report raise InputError {
  match value {
    Array(docs) => {
      if docs.is_empty() || docs.length() > 50 {
        raise InvalidInput("a run requires 1..50 documents")
      }
      merge_reports(
        docs.map(doc => input_document(doc, duplicates)),
        duplicates~,
      )
    }
    _ => input_document(value, duplicates)
  }
}

///|
/// Batch/embedding protocol. Errors are structured and never converted to empty reports.
pub fn evaluate_request(text : String) -> Json {
  try {
    if text.length() > 20000000 {
      raise InvalidInput("JSON request exceeds 20000000 code units")
    }
    let request = @json.parse(text, reject_duplicate_keys=true) catch {
      error => raise InvalidInput("invalid JSON: \{error}")
    }
    let operation = string_field(request, "op", "compare")
    if operation == "parse" {
      let doc = match field(request, "document") {
        Some(doc) => doc
        None => raise InvalidInput("missing document")
      }
      let report = parse_document(
        string_field(doc, "xml", ""),
        source=string_field(doc, "source", "<input>"),
      )
      return { "ok": true, "exit_code": 0, "report": report.to_json() }
    }
    if operation != "compare" {
      raise InvalidInput("unknown operation: \{operation}")
    }
    let duplicates = parse_duplicates(
      string_field(request, "duplicates", "error"),
    )
    let history = match field(request, "baselines") {
      Some(Array(runs)) if !runs.is_empty() && runs.length() <= 50 =>
        runs.map(run => input_run(run, duplicates))
      _ => raise InvalidInput("baselines must contain 1..50 chronological runs")
    }
    let candidate = match field(request, "candidate") {
      Some(value) => input_run(value, duplicates)
      None => raise InvalidInput("missing candidate")
    }
    let fail_on = match field(request, "fail_on") {
      None => default_config().fail_on
      Some(Array(items)) =>
        items.map(item => {
          match item {
            String(s) => s
            _ => raise InvalidInput("fail_on must contain strings")
          }
        })
      _ => raise InvalidInput("fail_on must be an array")
    }
    let config = diff_config(
      slowdown_pct=integer_field(request, "slowdown_pct", 50L, 1000000L).to_int(),
      slowdown_floor_us=integer_field(
        request, "slowdown_floor_us", 200000L, 9000000000000L,
      ),
      fail_on~,
    )
    let result = compare(history, candidate, config~)
    {
      "ok": true,
      "exit_code": Json(result.exit_code()),
      "report": result.to_json(),
    }
  } catch {
    Rejected(code, message) =>
      {
        "ok": false,
        "exit_code": 2,
        "error_code": Json(code),
        "error": Json(message),
      }
    error =>
      {
        "ok": false,
        "exit_code": 2,
        "error_code": "invalid_request",
        "error": Json(error.to_string()),
      }
  }
}
