///|
fn validate_keys(
  value : Json,
  allowed : Array[String],
  path : String,
) -> Unit raise InputError {
  match value {
    Object(fields) =>
      for key, _ in fields {
        if !allowed.contains(key) {
          raise UnknownField(path + "[" + Json(key).stringify() + "]")
        }
      }
    _ => raise InvalidInput("\{path} must be an object")
  }
}

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
  path : String,
) -> Report raise InputError {
  validate_keys(value, ["xml", "source"], path)
  let source = string_field(value, "source", "<input>")
  let xml = string_field(value, "xml", "")
  parse_report(xml, source~, duplicates~)
}

///|
fn input_run(
  value : Json,
  duplicates : DuplicatePolicy,
  path : String,
) -> Report raise InputError {
  match value {
    Array(docs) => {
      if docs.is_empty() || docs.length() > 50 {
        raise InvalidInput("a run requires 1..50 documents")
      }
      let reports : Array[Report] = []
      for i = 0; i < docs.length(); i = i + 1 {
        reports.push(input_document(docs[i], duplicates, "\{path}[\{i}]"))
      }
      merge_reports(reports, duplicates~)
    }
    _ => input_document(value, duplicates, path)
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
      validate_keys(request, ["op", "document"], "$")
      let doc = match field(request, "document") {
        Some(doc) => doc
        None => raise InvalidInput("missing document")
      }
      validate_keys(doc, ["xml", "source"], "$[\"document\"]")
      let report = parse_document(
        string_field(doc, "xml", ""),
        source=string_field(doc, "source", "<input>"),
      )
      return { "ok": true, "exit_code": 0, "report": report.to_json() }
    }
    if operation != "compare" {
      raise InvalidInput("unknown operation: \{operation}")
    }
    validate_keys(
      request,
      [
        "op", "baselines", "candidate", "duplicates", "fail_on", "slowdown_pct",
        "slowdown_floor_us",
      ],
      "$",
    )
    let duplicates = parse_duplicates(
      string_field(request, "duplicates", "error"),
    )
    let history = match field(request, "baselines") {
      Some(Array(runs)) if !runs.is_empty() && runs.length() <= 50 => {
        let reports : Array[Report] = []
        for i = 0; i < runs.length(); i = i + 1 {
          reports.push(input_run(runs[i], duplicates, "$[\"baselines\"][\{i}]"))
        }
        reports
      }
      _ => raise InvalidInput("baselines must contain 1..50 chronological runs")
    }
    let candidate = match field(request, "candidate") {
      Some(value) => input_run(value, duplicates, "$[\"candidate\"]")
      None => raise InvalidInput("missing candidate")
    }
    let fail_on = match field(request, "fail_on") {
      None => default_config().fail_on.iter().to_array()
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
    UnknownField(path) =>
      {
        "ok": false,
        "exit_code": 2,
        "error_code": "unknown_field",
        "error_path": Json(clipped(path, 2048)),
        "error": Json("unknown field at " + clipped(path, 2048)),
      }
    Rejected(code, message) =>
      {
        "ok": false,
        "exit_code": 2,
        "error_code": Json(code),
        "error": Json(clipped(message, 2048)),
      }
    error =>
      {
        "ok": false,
        "exit_code": 2,
        "error_code": "invalid_request",
        "error": Json(clipped(error.to_string(), 2048)),
      }
  }
}
