///|
/// Map structural cases in source order. None removes a case. Extension
/// subtrees are opaque; cases directly inside the root testsuites are supported.
pub fn JUnitDocument::map_cases(
  self : JUnitDocument,
  transform : (JUnitElement) -> JUnitElement? raise,
) -> JUnitDocument raise {
  ignore(self.to_xml())
  fn visit(element : JUnitElement) -> JUnitElement raise {
    let content = []
    for node in element.content {
      match node {
        Element(child) if child.name == "testcase" =>
          if transform(child) is Some(replacement) {
            if replacement.name != "testcase" {
              raise InvalidInput("map_cases must return testcase or None")
            }
            content.push(Element(replacement))
          }
        Element(child) if child.name == "testsuite" =>
          content.push(Element(visit(child)))
        _ => content.push(node)
      }
    }
    element.with_content(content)
  }
  let result = self.with_root(visit(self.root))
  ignore(result.to_xml())
  result
}

///|
/// Apply a transformation to top-level suites only. A bare suite is wrapped
/// in testsuites when removed. Nested suites remain editable via with_content.
pub fn JUnitDocument::map_suites(
  self : JUnitDocument,
  transform : (JUnitElement) -> JUnitElement? raise,
) -> JUnitDocument raise {
  ignore(self.to_xml())
  fn apply(suite : JUnitElement) -> JUnitElement? raise {
    let result = transform(suite)
    if result is Some(element) && element.name != "testsuite" {
      raise InvalidInput("map_suites must return testsuite or None")
    }
    result
  }
  let result = if self.root.name == "testsuite" {
    self.with_root(apply(self.root).unwrap_or(JUnitElement::new("testsuites")))
  } else {
    let content = []
    for node in self.root.content {
      match node {
        Element(child) if child.name == "testsuite" =>
          if apply(child) is Some(value) {
            content.push(Element(value))
          }
        _ => content.push(node)
      }
    }
    self.with_root(self.root.with_content(content))
  }
  ignore(result.to_xml())
  result
}

///|
/// Comparison projection deliberately retains the existing strict 0.2 profile.
pub fn JUnitDocument::to_report(
  self : JUnitDocument,
  source~ : String = "<input>",
) -> Report raise InputError {
  parse_document(self.to_xml(), source~)
}

///|
priv struct DocumentStats {
  mut tests : Int32
  mut failures : Int32
  mut errors : Int32
  mut skipped : Int32
  mut time : Int64?
}

///|
fn document_stats() -> DocumentStats {
  { tests: 0, failures: 0, errors: 0, skipped: 0, time: None, }
}

///|
fn DocumentStats::add(
  self : DocumentStats,
  other : DocumentStats,
) -> Unit raise InputError {
  self.tests = self.tests + other.tests
  self.failures = self.failures + other.failures
  self.errors = self.errors + other.errors
  self.skipped = self.skipped + other.skipped
  if other.time is Some(value) {
    let before = self.time.unwrap_or(0L)
    if value > 9223372036854775807L - before {
      raise Rejected(
        "invalid_time", "aggregate duration overflows Int64 microseconds",
      )
    }
    self.time = Some(before + value)
  }
}

///|
// Full Int64 range for document statistics; the comparison profile retains
// its own lower duration ceiling. Fractional digits beyond six are floored.
fn document_time_us(value : String) -> Int64? raise InputError {
  if value == "" {
    return None
  }
  let mut whole = 0L
  let mut fraction = 0L
  let mut decimals = 0
  let mut digits = 0
  let mut dot = false
  for ch in value {
    if ch == '.' && !dot {
      dot = true
      continue
    }
    if ch < '0' || ch > '9' {
      raise Rejected("invalid_time", "invalid decimal duration: \{value}")
    }
    let digit = (ch.to_int() - 48).to_int64()
    if dot {
      if decimals < 6 {
        fraction = fraction * 10L + digit
      }
      decimals = decimals + 1
    } else {
      if whole > 9223372036854L / 10L ||
        (whole == 9223372036854L / 10L && digit > 9223372036854L % 10L) {
        raise Rejected("invalid_time", "duration overflows Int64 microseconds")
      }
      whole = whole * 10L + digit
      digits = digits + 1
    }
  }
  if digits == 0 || (dot && decimals == 0) {
    raise Rejected("invalid_time", "invalid decimal duration: \{value}")
  }
  while decimals < 6 {
    fraction = fraction * 10L
    decimals = decimals + 1
  }
  if whole == 9223372036854L && fraction > 775807L {
    raise Rejected("invalid_time", "duration overflows Int64 microseconds")
  }
  Some(whole * 1000000L + fraction)
}

///|
fn document_count_case(
  element : JUnitElement,
) -> DocumentStats raise InputError {
  let stats = document_stats()
  stats.tests = 1
  stats.time = document_time_us(element.attribute("time").unwrap_or(""))
  let mut failure = false
  let mut error = false
  let mut skipped = false
  for child in element.elements() {
    match child.name {
      "failure" => failure = true
      "error" => error = true
      "skipped" => skipped = true
      _ => ()
    }
  }
  if error {
    stats.errors = 1
  } else if failure {
    stats.failures = 1
  } else if skipped {
    stats.skipped = 1
  }
  stats
}

///|
/// Recount structural cases (error > failure > skipped > passed), not result
/// elements. Preserve suite wall time unless overwrite_time is true. Missing
/// case times contribute no information; a partial sum is only known case time.
pub fn JUnitDocument::with_statistics(
  self : JUnitDocument,
  overwrite_time~ : Bool = false,
) -> JUnitDocument raise InputError {
  ignore(self.to_xml())
  fn visit(
    element : JUnitElement,
  ) -> (JUnitElement, DocumentStats) raise InputError {
    let stats = document_stats()
    let content = []
    for node in element.content {
      match node {
        Element(child) if child.name == "testcase" => {
          stats.add(document_count_case(child))
          content.push(node)
        }
        Element(child) if child.name == "testsuite" => {
          let (updated, child_stats) = visit(child)
          stats.add(child_stats)
          content.push(Element(updated))
        }
        _ => content.push(node)
      }
    }
    if !overwrite_time {
      if document_time_us(element.attribute("time").unwrap_or(""))
        is Some(value) {
        stats.time = Some(value)
      }
    }
    let mut result = element
      .with_content(content)
      .with_attribute("tests", stats.tests.to_string())
      .with_attribute("failures", stats.failures.to_string())
      .with_attribute("errors", stats.errors.to_string())
      .with_attribute("skipped", stats.skipped.to_string())
    result = match stats.time {
      Some(value) => result.with_attribute("time", document_seconds(value))
      None => result.without_attribute("time")
    }
    (result, stats)
  }
  let (root, _) = visit(self.root)
  let result = self.with_root(root)
  ignore(result.to_xml())
  result
}

///|
fn document_aggregate_attribute(name : String) -> Bool {
  match name {
    "tests"
    | "failures"
    | "errors"
    | "skipped"
    | "time"
    | "disabled"
    | "assertions" => true
    _ => false
  }
}

///|
fn document_same_misc(
  a : ReadOnlyArray[JUnitNode],
  b : ReadOnlyArray[JUnitNode],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    let same = match (a[i], b[i]) {
      (Text(x), Text(y)) | (Comment(x), Comment(y)) | (CData(x), CData(y)) =>
        x == y
      (Instruction(t, x), Instruction(u, y)) => t == u && x == y
      _ => false
    }
    if !same {
      return false
    }
  }
  true
}

///|
/// Concatenate report documents without coalescing suites, deduplicating cases
/// or interpreting retries. Conflicting testsuites metadata, namespace bindings
/// or outside-root content is rejected. Resolve conflicts explicitly first.
/// New root aggregate attributes are omitted; use with_statistics to recount.
pub fn merge_documents(
  documents : Array[JUnitDocument],
) -> JUnitDocument raise InputError {
  if documents.is_empty() {
    return JUnitDocument::new()
  }
  for document in documents {
    ignore(document.to_xml())
  }
  if documents.length() == 1 {
    return documents[0]
  }
  let first = documents[0]
  let mut metadata : JUnitElement? = None
  let content = []
  for i = 0; i < documents.length(); i = i + 1 {
    let document = documents[i]
    if !document_same_misc(first.before, document.before) ||
      !document_same_misc(first.after, document.after) ||
      first.declaration != document.declaration {
      raise Rejected(
        "merge_conflict",
        "document \{i}: outside-root content or declaration differs",
      )
    }
    let root = document.root
    if root.name == "testsuite" {
      content.push(Element(root))
    } else {
      let attrs = root.attributes
        .iter()
        .filter(pair => !document_aggregate_attribute(pair.0))
        .to_array()
      let current = JUnitElement::new("testsuites", attributes=attrs)
      match metadata {
        None => metadata = Some(current)
        Some(previous) =>
          if previous.attributes.length() != current.attributes.length() ||
            current.attributes
            .iter()
            .any(pair => previous.attribute(pair.0) != Some(pair.1)) {
            raise Rejected(
              "merge_conflict",
              "document \{i}: testsuites metadata or namespace bindings differ",
            )
          }
      }
      for node in root.content {
        content.push(node)
      }
    }
  }
  let root = metadata
    .unwrap_or(JUnitElement::new("testsuites"))
    .with_content(content)
  let result = { ..first, root, }
  ignore(result.to_xml())
  result
}
