///|
/// Full report tree, separate from the deliberately lossy comparison Report.
pub struct JUnitDocument {
  root : JUnitElement
  before : ReadOnlyArray[JUnitNode]
  after : ReadOnlyArray[JUnitNode]
  declaration : (String, String?, String?)?
}

///|
pub fn JUnitDocument::new(
  root~ : JUnitElement = JUnitElement::new("testsuites"),
) -> JUnitDocument {
  { root, before: [], after: [], declaration: None, }
}

///|
pub fn JUnitDocument::with_root(
  self : JUnitDocument,
  root : JUnitElement,
) -> JUnitDocument {
  { ..self, root, }
}

///|
priv struct DocumentFrame {
  name : String
  attributes : Array[(String, String)]
  content : Array[JUnitNode]
  core_context : Bool
}

///|
fn document_namespace(
  element : @xml.NamespaceElement,
  parent_core : Bool,
) -> Bool raise InputError {
  let name = element.name.qualified_name
  let core_context = parent_core &&
    (
      name == "testsuite" ||
      name == "testsuites" ||
      name == "testcase" ||
      name == "properties" ||
      name == "property" ||
      name == "system-out" ||
      name == "system-err" ||
      document_result_tag(name)
    )
  if core_context && element.name.namespace_uri != None {
    raise Rejected(
      "unsupported_namespace", "JUnit core elements must be unnamespaced",
    )
  }
  core_context
}

///|
fn document_input(text : String) -> Unit raise InputError {
  if text.length() > 10000000 {
    raise Rejected("limit_exceeded", "XML exceeds 10000000 UTF-16 units")
  }
  check_xml_attribute_budget(text)
}

///|
/// Read a complete XML tree. No DTD, entity loading, file or network access.
pub fn JUnitDocument::from_xml(text : String) -> JUnitDocument raise InputError {
  document_input(text)
  let reader = @xml.NamespaceReader::from_string(text)
  let stack : Array[DocumentFrame] = []
  let top : Array[JUnitNode] = []
  let mut declaration = None
  let mut events = 0
  let mut cases = 0
  while true {
    events = events + 1
    if events > 2000000 {
      raise Rejected("limit_exceeded", "XML event limit exceeded")
    }
    let event = reader.read_event() catch {
      error => raise Rejected("malformed_xml", "\{error}")
    }
    let node : JUnitNode? = match event.kind {
      Start(element) | Empty(element) => {
        let core_context = document_namespace(
          element,
          stack.last().map(frame => frame.core_context).unwrap_or(true),
        )
        if stack.length() >= 128 {
          raise Rejected("limit_exceeded", "XML depth exceeds 128")
        }
        if element.name.qualified_name == "testcase" {
          cases = cases + 1
          if cases > 100000 {
            raise Rejected("limit_exceeded", "more than 100000 testcases")
          }
        }
        let attrs = []
        for ns in element.namespace_declarations {
          let name = match ns.prefix {
            Some(prefix) => "xmlns:\{prefix}"
            None => "xmlns"
          }
          attrs.push((name, ns.namespace_uri))
        }
        for attr in element.attributes {
          attrs.push((attr.name.qualified_name, attr.value))
        }
        match event.kind {
          Start(_) => {
            stack.push({
              name: element.name.qualified_name,
              attributes: attrs,
              content: [],
              core_context,
            })
            None
          }
          _ =>
            Some(
              Element(
                JUnitElement::new(element.name.qualified_name, attributes=attrs),
              ),
            )
        }
      }
      End(_) => {
        guard stack.pop() is Some(frame) else {
          raise InvalidInput("unmatched closing element")
        }
        Some(
          Element(
            JUnitElement::new(
              frame.name,
              attributes=frame.attributes,
              content=frame.content,
            ),
          ),
        )
      }
      Text(value) => Some(Text(value))
      CData(value) => Some(CData(value))
      Comment(value) => Some(Comment(value))
      PI(target~, data~) => Some(Instruction(target, data))
      Decl(version~, encoding~, standalone~) => {
        if version != "1.0" || (encoding is Some(e) && e.to_lower() != "utf-8") {
          raise Rejected(
            "unsupported_encoding", "only XML 1.0 / UTF-8 is supported",
          )
        }
        declaration = Some((version, encoding, standalone))
        None
      }
      DocType(_) => raise Rejected("doctype", "DOCTYPE is unsupported")
      Eof => {
        if !stack.is_empty() {
          raise Rejected("malformed_xml", "unclosed XML elements")
        }
        break
      }
    }
    if node is Some(value) {
      match stack.last() {
        Some(frame) => frame.content.push(value)
        None => top.push(value)
      }
    }
  }
  let before = []
  let after = []
  let mut root = None
  for node in top {
    match node {
      Element(element) => {
        if root is Some(_) {
          raise InvalidInput("multiple XML roots")
        }
        root = Some(element)
      }
      _ => if root is None { before.push(node) } else { after.push(node) }
    }
  }
  guard root is Some(root) else { raise InvalidInput("missing XML root") }
  document_root(root)
  {
    root,
    before: ReadOnlyArray::from_array(before),
    after: ReadOnlyArray::from_array(after),
    declaration,
  }
}

///|
fn document_root(root : JUnitElement) -> Unit raise InputError {
  if root.name != "testsuite" && root.name != "testsuites" {
    raise InvalidInput("JUnit root must be testsuite or testsuites")
  }
}

///|
// xml 0.6.1 exposes write_event but keeps Event construction read-only.
// Obtain a validated event through its reader and verify exact decoded fields;
// malformed or injected markup cannot become a different output event.
fn document_event(kind : @xml.EventKind) -> @xml.Event raise @xml.WriterError {
  let text = match kind {
    PI(target~, data~) =>
      "<?\{target}\{if data == "" { "" } else { " " + data }}?>"
    Decl(version~, encoding~, standalone~) => {
      let out = StringBuilder()
      out.write_string("<?xml version=\"\{version}\"")
      if encoding is Some(value) {
        out.write_string(" encoding=\"\{value}\"")
      }
      if standalone is Some(value) {
        out.write_string(" standalone=\"\{value}\"")
      }
      out.write_string("?>")
      out.to_string()
    }
    _ => raise @xml.WriterError::InvalidContent("unsupported document event")
  }
  let event = @xml.Reader::from_string(text).read_event() catch {
    _ =>
      raise @xml.WriterError::InvalidContent(
        "invalid document declaration or instruction",
      )
  }
  if event.kind != kind {
    raise @xml.WriterError::InvalidContent(
      "document event changed during validation",
    )
  }
  event
}

///|
priv struct DocumentBudget {
  output : OutputBudget
  mut nodes : Int32
  mut cases : Int32
}

///|
fn document_escaped_units(text : String, attribute : Bool) -> Int64 {
  let mut units = 0L
  for ch in text {
    units = units +
      (match ch {
        '&' => 5L
        '<' | '>' => 4L
        '\'' | '"' => 6L
        '\r' => 5L
        '\n' if attribute => 5L
        '\t' if attribute => 4L
        _ => if ch.to_int() > 65535 { 2L } else { 1L }
      })
  }
  units
}

///|
fn document_measure(
  node : JUnitNode,
  budget : DocumentBudget,
  depth : Int32,
) -> Unit raise InputError {
  budget.nodes = budget.nodes +
    (match node {
      Element(element) => if element.content.is_empty() { 1 } else { 2 }
      Text(text) => if text == "" { 0 } else { 1 }
      _ => 1
    })
  if budget.nodes > 2000000 {
    raise Rejected("limit_exceeded", "XML event limit exceeded")
  }
  match node {
    Element(element) => {
      if depth > 128 {
        raise Rejected("limit_exceeded", "XML depth exceeds 128")
      }
      if element.name == "testcase" {
        budget.cases = budget.cases + 1
        if budget.cases > 100000 {
          raise Rejected("limit_exceeded", "more than 100000 testcases")
        }
      }
      if element.attributes.length() > 1024 {
        raise Rejected("limit_exceeded", "more than 1024 attributes")
      }
      budget.output.add(
        if element.content.is_empty() {
          3L + element.name.length().to_int64()
        } else {
          5L + 2L * element.name.length().to_int64()
        },
      )
      for attr in element.attributes {
        budget.output.add(
          4L + attr.0.length().to_int64() + document_escaped_units(attr.1, true),
        )
      }
      for child in element.content {
        document_measure(child, budget, depth + 1)
      }
    }
    Text(text) => budget.output.add(document_escaped_units(text, false))
    CData(text) => budget.output.add(12L + text.length().to_int64())
    Comment(text) => budget.output.add(7L + text.length().to_int64())
    Instruction(target, data) =>
      budget.output.add(
        4L +
        target.length().to_int64() +
        (if data == "" { 0L } else { 1L + data.length().to_int64() }),
      )
  }
}

///|
fn document_write_node(
  writer : @xml.Writer,
  node : JUnitNode,
) -> Unit raise @xml.WriterError {
  match node {
    Element(element) => {
      let attrs = element.attributes.iter().to_array()
      if element.content.is_empty() {
        writer.empty_element(element.name, attrs)
      } else {
        writer.start_element(element.name, attrs)
        for child in element.content {
          document_write_node(writer, child)
        }
        writer.end_element(element.name)
      }
    }
    Text(text) => writer.text(text)
    CData(text) => writer.cdata(text)
    Comment(text) => writer.comment(text)
    Instruction(target, data) =>
      writer.write_event(document_event(PI(target~, data~)))
  }
}

///|
/// Preserve authored statistics; call with_statistics explicitly after editing.
/// Namespace and XML validation complete before returning any output.
pub fn JUnitDocument::to_xml(
  self : JUnitDocument,
  max_units~ : Int64 = 10000000L,
) -> String raise InputError {
  if max_units > 10000000L {
    raise InvalidInput("XML output limit cannot exceed 10000000 units")
  }
  document_root(self.root)
  let budget = { output: output_budget(max_units), nodes: 1, cases: 0, }
  if self.declaration is Some((version, encoding, standalone)) {
    budget.nodes = budget.nodes + 1
    budget.output.add(
      18L +
      version.length().to_int64() +
      (match encoding {
        Some(value) => 12L + value.length().to_int64()
        None => 0L
      }) +
      (match standalone {
        Some(value) => 14L + value.length().to_int64()
        None => 0L
      }),
    )
    if version != "1.0" || (encoding is Some(e) && e.to_lower() != "utf-8") {
      raise Rejected(
        "unsupported_encoding", "only XML 1.0 / UTF-8 is supported",
      )
    }
  }
  for node in self.before {
    document_measure(node, budget, 1)
  }
  document_measure(Element(self.root), budget, 1)
  for node in self.after {
    document_measure(node, budget, 1)
  }
  let writer = @xml.Writer::new()
  let text = (fn() raise @xml.WriterError {
    if self.declaration is Some((version, encoding, standalone)) {
      writer.write_event(document_event(Decl(version~, encoding~, standalone~)))
    }
    for node in self.before {
      document_write_node(writer, node)
    }
    document_write_node(writer, Element(self.root))
    for node in self.after {
      document_write_node(writer, node)
    }
    writer.to_string()
  })() catch {
    _ =>
      raise Rejected(
        "invalid_xml_output", "invalid XML name, character, content or structure",
      )
  }
  if text.length().to_int64() > max_units {
    raise Rejected("output_limit", "serialized XML exceeds output budget")
  }
  let reader = @xml.NamespaceReader::from_string(text)
  let contexts : Array[Bool] = []
  while true {
    let event = reader.read_event() catch {
      error => raise Rejected("invalid_xml_output", "\{error}")
    }
    match event.kind {
      Start(element) =>
        contexts.push(
          document_namespace(element, contexts.last().unwrap_or(true)),
        )
      Empty(element) =>
        ignore(document_namespace(element, contexts.last().unwrap_or(true)))
      End(_) => ignore(contexts.pop())
      Eof => break
      _ => ()
    }
  }
  text
}

///|
/// Deliver validated XML to a caller-owned file, stream or other sink.
/// Sink errors propagate; atomic file replacement belongs to the caller.
pub fn JUnitDocument::write_to(
  self : JUnitDocument,
  write : (String) -> Unit raise,
  max_units~ : Int64 = 10000000L,
) -> Unit raise {
  write(self.to_xml(max_units~))
}
