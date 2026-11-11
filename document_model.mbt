///|
/// Ordered XML content. Editing returns new values; no shared mutable children.
pub(all) enum JUnitNode {
  Element(JUnitElement)
  Text(String)
  CData(String)
  Comment(String)
  Instruction(String, String)
}

///|
/// A report element, including producer-specific attributes and children.
/// XML validity is checked when a document is serialized.
pub struct JUnitElement {
  name : String
  attributes : ReadOnlyArray[(String, String)]
  content : ReadOnlyArray[JUnitNode]
}

///|
pub fn JUnitElement::new(
  name : String,
  attributes~ : Array[(String, String)] = [],
  content~ : Array[JUnitNode] = [],
) -> JUnitElement {
  {
    name,
    attributes: ReadOnlyArray::from_array(attributes.iter().to_array()),
    content: ReadOnlyArray::from_array(content.iter().to_array()),
  }
}

///|
pub fn JUnitElement::attribute(self : JUnitElement, name : String) -> String? {
  for pair in self.attributes {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Set one attribute, replacing all earlier occurrences of that name.
pub fn JUnitElement::with_attribute(
  self : JUnitElement,
  name : String,
  value : String,
) -> JUnitElement {
  let attrs = self.attributes.iter().filter(pair => pair.0 != name).to_array()
  attrs.push((name, value))
  { ..self, attributes: ReadOnlyArray::from_array(attrs), }
}

///|
pub fn JUnitElement::without_attribute(
  self : JUnitElement,
  name : String,
) -> JUnitElement {
  {
    ..self,
    attributes: ReadOnlyArray::from_array(
      self.attributes.iter().filter(pair => pair.0 != name).to_array(),
    ),
  }
}

///|
pub fn JUnitElement::with_content(
  self : JUnitElement,
  content : Array[JUnitNode],
) -> JUnitElement {
  { ..self, content: ReadOnlyArray::from_array(content.iter().to_array()), }
}

///|
pub fn JUnitElement::append(
  self : JUnitElement,
  child : JUnitNode,
) -> JUnitElement {
  let content = self.content.iter().to_array()
  content.push(child)
  { ..self, content: ReadOnlyArray::from_array(content), }
}

///|
/// Direct child elements, in source order. An omitted name selects all.
pub fn JUnitElement::elements(
  self : JUnitElement,
  name~ : String? = None,
) -> Array[JUnitElement] {
  let result = []
  for node in self.content {
    if node is Element(child) && (name == None || name == Some(child.name)) {
      result.push(child)
    }
  }
  result
}

///|
pub fn JUnitElement::suite(name : String) -> JUnitElement {
  JUnitElement::new("testsuite", attributes=[("name", name)])
}

///|
pub fn JUnitElement::testcase(
  name : String,
  classname~ : String? = None,
  time_us~ : Int64? = None,
) -> JUnitElement raise InputError {
  if name == "" {
    raise InvalidInput("testcase name must not be empty")
  }
  let mut element = JUnitElement::new("testcase", attributes=[("name", name)])
  if classname is Some(value) {
    element = element.with_attribute("classname", value)
  }
  if time_us is Some(value) {
    if value < 0L {
      raise InvalidInput("testcase time must be nonnegative microseconds")
    }
    element = element.with_attribute("time", document_seconds(value))
  }
  element
}

///|
/// Final or Surefire retry result. Multiple result elements remain separate.
pub fn JUnitElement::result(
  kind : String,
  message~ : String = "",
  type_~ : String = "",
  body~ : String = "",
) -> JUnitElement raise InputError {
  if !document_result_tag(kind) {
    raise InvalidInput("unsupported JUnit result tag: \{kind}")
  }
  JUnitElement::new(kind, attributes=[("message", message), ("type", type_)], content=[
    Text(body),
  ])
}

///|
/// Append a property without discarding existing or duplicate property entries.
pub fn JUnitElement::add_property(
  self : JUnitElement,
  name : String,
  value : String,
) -> JUnitElement {
  let property = Element(
    JUnitElement::new("property", attributes=[("name", name), ("value", value)]),
  )
  let content = self.content.iter().to_array()
  for i = 0; i < content.length(); i = i + 1 {
    if content[i] is Element(child) && child.name == "properties" {
      content[i] = Element(child.append(property))
      return self.with_content(content)
    }
  }
  content.push(Element(JUnitElement::new("properties", content=[property])))
  self.with_content(content)
}

///|
/// Replace direct system-out or system-err children with one text element.
pub fn JUnitElement::with_output(
  self : JUnitElement,
  kind : String,
  text : String,
) -> JUnitElement raise InputError {
  if kind != "system-out" && kind != "system-err" {
    raise InvalidInput("output kind must be system-out or system-err")
  }
  let content = self.content
    .iter()
    .filter(node => {
      match node {
        Element(child) => child.name != kind
        _ => true
      }
    })
    .to_array()
  content.push(Element(JUnitElement::new(kind, content=[Text(text)])))
  self.with_content(content)
}

///|
/// Replace final result elements, preserving retry markers and other metadata.
pub fn JUnitElement::with_results(
  self : JUnitElement,
  results : Array[JUnitElement],
) -> JUnitElement raise InputError {
  if self.name != "testcase" {
    raise InvalidInput("results belong to testcase")
  }
  for result in results {
    if result.name != "failure" &&
      result.name != "error" &&
      result.name != "skipped" {
      raise InvalidInput("final result must be failure, error or skipped")
    }
  }
  let content = self.content
    .iter()
    .filter(node => {
      match node {
        Element(child) =>
          child.name != "failure" &&
          child.name != "error" &&
          child.name != "skipped"
        _ => true
      }
    })
    .to_array()
  for result in results {
    content.push(Element(result))
  }
  self.with_content(content)
}

///|
fn document_result_tag(name : String) -> Bool {
  match name {
    "failure"
    | "error"
    | "skipped"
    | "flakyFailure"
    | "flakyError"
    | "rerunFailure"
    | "rerunError" => true
    _ => false
  }
}

///|
fn document_seconds(value : Int64) -> String {
  let fraction = (value % 1000000L).to_string()
  "\{value / 1000000L}.\{String::make(6 - fraction.length(), '0')}\{fraction}"
}
