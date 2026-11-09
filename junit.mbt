///|
priv struct CaseBuilder {
  scope : Int32
  id : TestId
  name : String
  classname : String?
  final_results : Array[String]
  interim_results : Array[String]
  suite_order : Int32
  time_us : Int64?
  mut failed : Int32
  mut errored : Int32
  mut skipped : Int32
  mut flaky_count : Int32
  mut rerun_count : Int32
  mut message : String
  mut message_truncated : Bool
}

///|
fn CaseBuilder::finish(
  self : CaseBuilder,
  source : String,
  diagnostics : Array[Diagnostic],
  document_order : Int32,
  source_units : Int64,
) -> TestCase raise InputError {
  let retries = self.flaky_count + self.rerun_count
  if self.skipped > 0 && retries > 0 {
    raise Rejected(
      "retry_conflict",
      "\{source}: skipped cannot be combined with retry elements",
    )
  }
  let outer_failure = self.failed > 0 || self.errored > 0
  if !outer_failure && self.rerun_count > 0 {
    raise Rejected(
      "retry_conflict",
      "\{source}: rerun elements require an outer failure/error",
    )
  }
  if outer_failure && self.flaky_count > 0 {
    diagnostics.push(
      diagnostic(
        source,
        "contradictory_retry",
        "document index \{document_order}: \{self.id.preview()}; outcome is failure/error; flaky markers retained",
      ),
    )
  }
  if self.failed + self.errored + self.skipped > 1 {
    diagnostics.push(
      diagnostic(
        source,
        "multiple_outcomes",
        "document index \{document_order}: \{self.id.preview()}; precedence is error > failure > skipped > passed",
      ),
    )
  }
  let outcome = if self.errored > 0 {
    Errored
  } else if self.failed > 0 {
    Failed
  } else if self.skipped > 0 {
    Skipped
  } else {
    Passed
  }
  if self.message_truncated {
    diagnostics.push(
      diagnostic(
        source,
        "message_truncated",
        "document index \{document_order}: \{self.id.preview()}; message clipped at 2048 UTF-16 units",
      ),
    )
  }
  {
    id: self.id,
    scope: self.scope,
    name: self.name,
    classname: self.classname,
    final_results: ReadOnlyArray::from_array(self.final_results),
    interim_results: ReadOnlyArray::from_array(self.interim_results),
    suite_order: self.suite_order,
    document_order,
    outcome,
    attempts: retries + 1,
    flaky: self.flaky_count > 0,
    time_us: self.time_us,
    message: self.message,
    source,
    source_units,
  }
}

///|
fn append_message(builder : CaseBuilder, text : String) -> Unit {
  if builder.message_truncated {
    return
  }
  let remaining = 2048 - builder.message.length()
  let prefix = truncate_utf16(text, remaining)
  builder.message_truncated = prefix.length() < text.length()
  builder.message = builder.message + prefix
}

///|
/// Parse the documented unnamespaced JUnit profile; no I/O or external entities.
pub fn parse_document(
  text : String,
  source~ : String = "<input>",
) -> Report raise InputError {
  if text.length() > 10000000 {
    raise Rejected(
      "limit_exceeded",
      "\{source}: XML exceeds 10000000 UTF-16 code units",
    )
  }
  check_xml_attribute_budget(text)
  let source_units = string_json_units(source)
  let reader = @xml.Reader::from_string(text)
  let tags : Array[String] = []
  let pool = new_scope_pool()
  let suite_tokens : Array[Int32] = []
  let suite_orders : Array[Int32] = []
  let mut next_suite = 0
  let cases : Array[TestCase] = []
  let diagnostics : Array[Diagnostic] = []
  let unknown : Map[String, Bool] = Map([])
  let mut current : CaseBuilder? = None
  let mut case_depth = 0
  let mut message_depth = 0
  let mut message_body_started = false
  let mut root_seen = false
  let mut events = 0
  while true {
    events = events + 1
    if events > 2000000 {
      raise Rejected("limit_exceeded", "\{source}: XML event limit exceeded")
    }
    let event = reader.read_event() catch {
      error => raise Rejected("malformed_xml", "\{source}: \{error}")
    }
    match event.kind {
      Start(element) | Empty(element) => {
        let empty = match event.kind {
          Empty(_) => true
          _ => false
        }
        let tag = element.name
        let parent = tags.last().unwrap_or("")
        let depth = tags.length() + 1
        if depth > 128 {
          raise Rejected("limit_exceeded", "\{source}: XML depth exceeds 128")
        }
        if root_seen && depth == 1 {
          raise Rejected("invalid_structure", "\{source}: multiple XML roots")
        }
        if !root_seen {
          if tag != "testsuite" && tag != "testsuites" {
            raise Rejected(
              "invalid_structure",
              "\{source}: root must be testsuite or testsuites",
            )
          }
          root_seen = true
          // Node's JUnit reporter can place cases directly under testsuites.
          // Reserve order zero for these cases before any nested suites.
          if tag == "testsuites" {
            next_suite = 1
          }
        }
        let root_xsi = depth == 1 &&
          element.get("xmlns:xsi") ==
          Some("http://www.w3.org/2001/XMLSchema-instance")
        if tag.contains(":") ||
          element.attributes.any(a => {
            if root_xsi &&
              (
                a.name == "xmlns:xsi" ||
                a.name == "xsi:noNamespaceSchemaLocation"
              ) {
              false
            } else {
              a.name == "xmlns" || a.name.contains(":")
            }
          }) {
          raise Rejected(
            "unsupported_namespace",
            "\{source}: only root Surefire xsi schema metadata is supported; namespaced JUnit elements are not",
          )
        }
        if tag == "testsuite" {
          if depth > 1 && parent != "testsuites" && parent != "testsuite" {
            raise Rejected(
              "invalid_structure",
              "\{source}: testsuite in unsupported location",
            )
          }
          if current is Some(_) {
            raise Rejected(
              "invalid_structure",
              "\{source}: suite inside testcase",
            )
          }
          let parent_scope = suite_tokens.last().unwrap_or(0)
          suite_tokens.push(
            pool.intern(parent_scope, element.get("name").unwrap_or("")),
          )
          suite_orders.push(next_suite)
          next_suite = next_suite + 1
        } else if tag == "testsuites" {
          if depth > 1 {
            raise Rejected(
              "invalid_structure",
              "\{source}: nested testsuites is unsupported",
            )
          }
        } else if tag == "testcase" {
          let root_case = parent == "testsuites" && depth == 2
          if (parent != "testsuite" && !root_case) || current is Some(_) {
            raise Rejected(
              "invalid_structure",
              "\{source}: testcase must be directly inside testsuite or root testsuites",
            )
          }
          let name = element.get("name").unwrap_or("")
          if name == "" {
            raise Rejected(
              "missing_name",
              "\{source}: testcase requires a nonempty name",
            )
          }
          let scope = match element.get("classname") {
            Some(classname) => pool.intern(-1, classname)
            None => suite_tokens.last().unwrap_or(0)
          }
          let id = match element.get("classname") {
            Some(classname) => Class(classname, name)
            None => SuitePath(pool.scopes[scope].path, name)
          }
          let time_us = parse_duration(element.get("time").unwrap_or("")) catch {
            error => raise Rejected("invalid_time", "\{source}: \{error}")
          }
          current = Some({
            id,
            scope,
            name,
            classname: element.get("classname"),
            final_results: [],
            interim_results: [],
            suite_order: suite_orders.last().unwrap_or(0),
            time_us,
            failed: 0,
            errored: 0,
            skipped: 0,
            flaky_count: 0,
            rerun_count: 0,
            message: "",
            message_truncated: false,
          })
          case_depth = depth
        } else if tag == "failure" ||
          tag == "error" ||
          tag == "skipped" ||
          tag == "flakyFailure" ||
          tag == "flakyError" ||
          tag == "rerunFailure" ||
          tag == "rerunError" {
          guard current is Some(builder) && depth == case_depth + 1 else {
            raise Rejected(
              "invalid_structure",
              "\{source}: \{tag} must be directly inside testcase",
            )
          }
          match tag {
            "failure" => builder.failed = builder.failed + 1
            "error" => builder.errored = builder.errored + 1
            "skipped" => builder.skipped = builder.skipped + 1
            "flakyFailure" | "flakyError" =>
              builder.flaky_count = builder.flaky_count + 1
            _ => builder.rerun_count = builder.rerun_count + 1
          }
          if tag == "failure" || tag == "error" || tag == "skipped" {
            builder.final_results.push(tag)
          } else {
            builder.interim_results.push(tag)
          }
          if builder.message != "" {
            append_message(builder, "\n")
          }
          append_message(builder, element.get("message").unwrap_or(""))
          if !empty {
            message_depth = depth
            message_body_started = false
          }
        } else if tag != "properties" &&
          tag != "property" &&
          tag != "system-out" &&
          tag != "system-err" &&
          tag != "stackTrace" {
          if !unknown.contains(tag) {
            unknown[tag] = true
            diagnostics.push(
              diagnostic(source, "unknown_element", "ignored element: \{tag}"),
            )
          }
        }
        if empty {
          if tag == "testcase" {
            guard current is Some(builder) else {
              raise InvalidInput("missing testcase state")
            }
            cases.push(
              builder.finish(source, diagnostics, cases.length(), source_units),
            )
            current = None
          }
          if tag == "testsuite" {
            ignore(suite_tokens.pop())
            ignore(suite_orders.pop())
          }
        } else {
          tags.push(tag)
        }
        if cases.length() > 100000 {
          raise Rejected(
            "limit_exceeded",
            "\{source}: more than 100000 testcases",
          )
        }
      }
      End(tag) => {
        if tags.last() != Some(tag) {
          raise Rejected("malformed_xml", "mismatched XML closing element")
        }
        if tag == "testcase" {
          guard current is Some(builder) else {
            raise InvalidInput("\{source}: unmatched testcase")
          }
          cases.push(
            builder.finish(source, diagnostics, cases.length(), source_units),
          )
          current = None
          if cases.length() > 100000 {
            raise Rejected(
              "limit_exceeded",
              "\{source}: more than 100000 testcases",
            )
          }
        }
        if tag == "testsuite" {
          ignore(suite_tokens.pop())
          ignore(suite_orders.pop())
        }
        if tags.length() == message_depth {
          message_depth = 0
        }
        ignore(tags.pop())
      }
      Text(value) | CData(value) =>
        if message_depth > 0 &&
          !tags.contains("system-out") &&
          !tags.contains("system-err") {
          if current is Some(builder) {
            if !message_body_started && value != "" {
              if builder.message != "" {
                append_message(builder, "\n")
              }
              message_body_started = true
            }
            append_message(builder, value)
          }
        }
      DocType(_) =>
        raise Rejected("doctype", "\{source}: DOCTYPE is unsupported")
      Decl(encoding~, ..) =>
        if encoding is Some(e) && e.to_lower() != "utf-8" {
          raise Rejected(
            "unsupported_encoding",
            "\{source}: only UTF-8 XML is supported",
          )
        }
      Eof => {
        if !tags.is_empty() || current is Some(_) {
          raise Rejected("malformed_xml", "truncated XML document")
        }
        break
      }
      _ => ()
    }
  }
  if !root_seen {
    raise Rejected("malformed_xml", "\{source}: empty XML")
  }
  // junitparser iterates a suite's direct cases before its nested suites.
  cases.sort_by((a, b) => {
    let c = a.suite_order.compare(b.suite_order)
    if c != 0 {
      c
    } else {
      a.document_order.compare(b.document_order)
    }
  })
  {
    cases: ReadOnlyArray::from_array(cases),
    diagnostics: ReadOnlyArray::from_array(diagnostics),
    scopes: ReadOnlyArray::from_array(pool.scopes),
  }
}

///|
/// Normalize one document. Explicit attempts always use original document order.
pub fn parse_report(
  text : String,
  source~ : String = "<input>",
  duplicates~ : DuplicatePolicy = Reject,
) -> Report raise InputError {
  let document = parse_document(text, source~)
  merge_reports([document], duplicates~)
}
