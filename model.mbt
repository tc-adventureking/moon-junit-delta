///|
/// Final outcome is separate from evidence of inconsistent attempts.
#derive(Eq)
pub(all) enum Outcome {
  Passed
  Failed
  Errored
  Skipped
}

///|
#derive(Eq)
pub(all) enum DuplicatePolicy {
  Reject
  Attempts
}

///|
/// Tagged identity prevents class names from colliding with fallback suite paths.
#derive(Eq)
pub(all) enum TestId {
  Class(String, String)
  SuitePath(Array[String], String)
}

///|
#derive(Eq)
pub struct TestCase {
  id : TestId
  name : String
  classname : String?
  final_results : Array[String]
  interim_results : Array[String]
  suite_order : Int32
  document_order : Int32
  outcome : Outcome
  attempts : Int32
  flaky : Bool
  time_us : Int64?
  message : String
  source : String
}

///|
#derive(Eq)
pub struct Diagnostic {
  source : String
  code : String
  message : String
}

///|
#derive(Eq)
pub struct Report {
  cases : Array[TestCase]
  diagnostics : Array[Diagnostic]
}

///|
#derive(Eq)
pub(all) suberror InputError {
  InvalidInput(String)
  Rejected(String, String)
  UnknownField(String)
}

///|
pub fn TestId::to_json(self : TestId) -> Json {
  match self {
    Class(classname, name) => ["class", Json(classname), Json(name)]
    SuitePath(path, name) => ["suite", Json(path), Json(name)]
  }
}

///|
pub fn TestId::key(self : TestId) -> String {
  self.to_json().stringify()
}

///|
pub fn Outcome::label(self : Outcome) -> String {
  match self {
    Passed => "passed"
    Failed => "failed"
    Errored => "errored"
    Skipped => "skipped"
  }
}

///|
/// Decimal seconds, floored to microseconds. Bounds keep comparison arithmetic safe.
pub fn parse_duration(value : String) -> Int64? raise InputError {
  if value == "" {
    return None
  }
  let mut whole : Int64 = 0L
  let mut fraction : Int64 = 0L
  let mut digits = 0
  let mut before = 0
  let mut dot = false
  for ch in value {
    if ch == '.' && !dot {
      dot = true
      continue
    }
    if ch < '0' || ch > '9' {
      raise InvalidInput("invalid decimal time: \{value}")
    }
    let digit = (ch.to_int() - 48).to_int64()
    if dot {
      if digits < 6 {
        fraction = fraction * 10L + digit
      }
      digits = digits + 1
    } else {
      before = before + 1
      if whole > 9000000L / 10L {
        raise InvalidInput("time exceeds 9000000 seconds")
      }
      whole = whole * 10L + digit
      if whole > 9000000L {
        raise InvalidInput("time exceeds 9000000 seconds")
      }
    }
  }
  if before == 0 || (dot && digits == 0) {
    raise InvalidInput("invalid decimal time: \{value}")
  }
  while digits < 6 {
    fraction = fraction * 10L
    digits = digits + 1
  }
  let result = whole * 1000000L + fraction
  if result > 9000000000000L {
    raise InvalidInput("time exceeds 9000000 seconds")
  }
  Some(result)
}

///|
fn diagnostic(source : String, code : String, message : String) -> Diagnostic {
  { source, code, message, }
}

///|
/// Ordered merge. Only explicit Attempts opts into interpreting duplicates as retries.
pub fn merge_reports(
  reports : Array[Report],
  duplicates~ : DuplicatePolicy = Reject,
) -> Report raise InputError {
  let cases : Array[TestCase] = []
  let index : Map[String, Int32] = Map([])
  let diagnostics : Array[Diagnostic] = []
  for report in reports {
    diagnostics.append(report.diagnostics)
    for current in report.cases {
      let key = current.id.key()
      match index.get(key) {
        None => {
          index[key] = cases.length()
          cases.push(current)
        }
        Some(i) => {
          let old = cases[i]
          if duplicates == Reject {
            raise InvalidInput(
              "duplicate test ID \{key} in \{old.source} and \{current.source}",
            )
          }
          if old.attempts > 1000000 - current.attempts {
            raise InvalidInput("too many attempts for \{key}")
          }
          cases[i] = {
            ..current,
            attempts: old.attempts + current.attempts,
            flaky: old.flaky || current.flaky || old.outcome != current.outcome,
          }
          diagnostics.push(
            diagnostic(
              current.source,
              "duplicate_attempt",
              "\{key}: final attempt wins; previous source \{old.source}",
            ),
          )
        }
      }
    }
  }
  { cases, diagnostics, }
}

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend DuplicatePolicy with Eq::{equal, not_equal}

///|
pub extend TestId with Eq::{equal, not_equal}

///|
pub extend TestCase with Eq::{equal, not_equal}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend InputError with Eq::{equal, not_equal}

///|
pub extend InputError with Show::{output, to_string}

///|
pub impl Show for InputError with fn output(self, logger) {
  match self {
    InvalidInput(message) => logger.write_string(message)
    Rejected(code, message) => logger.write_string("[\{code}] \{message}")
    UnknownField(path) => logger.write_string("unknown field at \{path}")
  }
}

///|
/// Raw result flags match junitparser's independent Boolean properties.
pub fn TestCase::is_passed(self : TestCase) -> Bool {
  self.final_results.is_empty()
}

///|
pub fn TestCase::is_failure(self : TestCase) -> Bool {
  self.final_results.contains("failure")
}

///|
pub fn TestCase::is_error(self : TestCase) -> Bool {
  self.final_results.contains("error")
}

///|
pub fn TestCase::is_skipped(self : TestCase) -> Bool {
  self.final_results.contains("skipped")
}

///|
pub fn TestCase::is_flaky(self : TestCase) -> Bool {
  self.interim_results.any(x => x == "flakyFailure" || x == "flakyError")
}

///|
pub fn TestCase::is_rerun(self : TestCase) -> Bool {
  self.interim_results.any(x => x == "rerunFailure" || x == "rerunError")
}
