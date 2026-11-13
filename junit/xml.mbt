///|
fn expanded_name(name : @xml.XmlName) -> String {
  match name.namespace_uri {
    Some(uri) if uri != "" => "{\{uri}}\{name.local_name}"
    _ => name.local_name
  }
}

///|
fn split_name(name : String) -> (String, String) {
  if name.has_prefix("{") {
    if name.find("}") is Some(end) {
      return (name[1:end].to_owned(), name[end + 1:].to_owned())
    }
  }
  ("", name)
}

///|
fn parsed_element(
  element : @xml.NamespaceElement,
  arena : Arena?,
) -> Element raise JUnitError {
  let node = match arena {
    Some(arena) => allocate_in(arena, Tag, expanded_name(element.name))
    None => allocate_element(Tag, expanded_name(element.name))
  }
  node.state().prefix = Some(element.name.prefix.unwrap_or(""))
  node.state().default_tag = element.name.qualified_name
  if element.attributes.length() + element.namespace_declarations.length() >
    1024 {
    raise LimitExceeded("element exceeds 1024 attributes")
  }
  for declaration in element.namespace_declarations {
    node.state().namespaces.push(
      (declaration.prefix.unwrap_or(""), declaration.namespace_uri),
    )
  }
  for attribute in element.attributes {
    let name = expanded_name(attribute.name)
    node.state().attributes.push((name, attribute.value))
    if attribute.name.prefix is Some(prefix) {
      node.state().attribute_prefixes[name] = prefix
    }
  }
  node
}

///|
/// Parse XML using the shared XML engine. Internal entities and DTD defaults,
/// comments and processing instructions are supported; CDATA becomes text.
/// Unicode input with an encoding declaration is rejected, as by lxml.
pub fn Element::from_string(source : String) -> Element raise JUnitError {
  parse_element(source, unicode_input=true)
}

///|
/// Parse already decoded XML, including a declaration. Byte/encoding adapters
/// can call this after decoding; an XML encoding declaration is descriptive.
pub fn Element::from_decoded(source : String) -> Element raise JUnitError {
  parse_element(source, unicode_input=false)
}

///|
fn parse_element(
  source : String,
  unicode_input~ : Bool,
) -> Element raise JUnitError {
  if source.length() > 10000000 {
    raise LimitExceeded("XML exceeds 10000000 units")
  }
  let reader = @xml.NamespaceReader::from_string(source)
  let stack : Array[Element] = []
  let mut root : Element? = None
  let prolog : Array[String] = []
  let epilog : Array[String] = []
  let mut doctype_end = -1
  let mut doctype : (String, String)? = None
  let pre_doctype : Array[String] = []
  let defaults : Map[String, Array[(String, String)]] = Map([])
  let mut events = 0
  while true {
    let event = reader.read_event() catch {
      error => raise ParseError(error.to_string())
    }
    events += 1
    if events > 2000000 {
      raise LimitExceeded("XML exceeds 2000000 events")
    }
    match event.kind {
      Decl(encoding~, ..) =>
        if unicode_input && encoding is Some(_) {
          raise InvalidValue(
            "Unicode XML must not contain an encoding declaration; decode bytes first",
          )
        }
      Start(element) | Empty(element) => {
        if stack.length() >= 128 {
          raise LimitExceeded("XML nesting exceeds 128")
        }
        let node = parsed_element(element, root.map(r => r.arena))
        node.state().doctype = doctype
        node.state().pre_doctype = pre_doctype
        if stack.last() is Some(parent) {
          node.state().defaults = parent.state().defaults
          parent.state().children_.push(node.id)
          node.state().parent_ = Some(parent.id)
        } else {
          node.state().defaults = defaults
          root = Some(node)
        }
        if event.kind is Start(_) {
          stack.push(node)
        }
      }
      End(_) => ignore(stack.pop())
      Text(text) | CData(text) =>
        if stack.last() is Some(parent) {
          if parent.state().children_.last() is Some(id) {
            let child = parent.handle(id)
            child.state().trailing = Some(
              child.state().trailing.unwrap_or("") + text,
            )
          } else {
            parent.state().value = Some(
              parent.state().value.unwrap_or("") + text,
            )
          }
        }
      Comment(text) =>
        if stack.last() is Some(parent) {
          let node = allocate_in(parent.arena, Comment, "#comment")
          node.state().value = Some(text)
          parent.state().children_.push(node.id)
          node.state().parent_ = Some(parent.id)
        } else if event.span.start.offset >= doctype_end {
          let text = "<!--\{text}-->"
          if root is None {
            prolog.push(text)
          } else {
            epilog.push(text)
          }
        }
      PI(target~, data~) =>
        if stack.last() is Some(parent) {
          let node = allocate_in(parent.arena, Instruction, target)
          node.state().value = Some(data)
          parent.state().children_.push(node.id)
          node.state().parent_ = Some(parent.id)
        } else if event.span.start.offset >= doctype_end {
          let text = if data == "" {
            "<?\{target}?>"
          } else {
            "<?\{target} \{data}?>"
          }
          if root is None {
            prolog.push(text)
          } else {
            epilog.push(text)
          }
        }
      DocType(name) => {
        doctype_end = event.span.end.offset
        doctype = Some(
          (name, source[event.span.start.offset:doctype_end].to_owned()),
        )
        pre_doctype.append(prolog)
        prolog.clear()
        // Keep defaults as document metadata, instead of injecting them into
        // events. Entity replacement intentionally flattens source spans in
        // the XML engine, so spans cannot reliably identify defaulted fields.
        for (tag, attributes) in reader.reader.default_attributes.to_array() {
          defaults[tag] = attributes.map(fn(attribute) {
            let value = if reader.reader.attr_types.get(
                tag + ":" + attribute.name,
              ) ==
              Some("CDATA") {
              attribute.value
            } else {
              attribute.value
              .split(" ")
              .filter(part => !part.is_empty())
              .map(part => part.to_owned())
              .join(" ")
            }
            (attribute.name, value)
          })
          // Namespace defaults still participate in name resolution.
          reader.reader.default_attributes[tag] = attributes.filter(attribute => {
            attribute.name == "xmlns" || attribute.name.has_prefix("xmlns:")
          })
        }
      }
      Eof => break
    }
  }
  match root {
    Some(root) => {
      root.state().prolog.append(prolog)
      root.state().epilog.append(epilog)
      root
    }
    None => raise ParseError("missing document element")
  }
}

///|
fn xml_text(text : String, attribute~ : Bool = false) -> String {
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' if attribute => out.write_string("&quot;")
      '\r' => out.write_string("&#13;")
      '\n' if attribute => out.write_string("&#10;")
      '\t' if attribute => out.write_string("&#9;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn Element::namespace_scope(self : Element) -> Array[(String, String)] {
  let lineage = [self]
  let mut parent = self.parent()
  while parent is Some(node) {
    lineage.push(node)
    parent = node.parent()
  }
  let result : Array[(String, String)] = []
  let seen : Map[String, Bool] = Map([])
  for node in lineage {
    for (prefix, uri) in node.state().namespaces {
      if !seen.contains(prefix) {
        seen[prefix] = true
        result.push((prefix, uri))
      }
    }
  }
  result
}

///|
// Find namespace bindings used in this subtree but declared above its root.
// Copying or moving the root must retain those bindings on the new root.
fn Element::required_namespaces(self : Element) -> Array[(String, String)] {
  let required : Array[(String, String)] = []
  for node in self.iter() {
    if !node.is_element() {
      continue
    }
    let uses : Array[(String, String)] = []
    let (uri, _) = split_name(node.tag())
    if uri != "" {
      uses.push((node.state().prefix.unwrap_or(""), uri))
    }
    for (key, _) in node.state().attributes {
      let (uri, _) = split_name(key)
      if uri != "" && uri != "http://www.w3.org/XML/1998/namespace" {
        if node.state().attribute_prefixes.get(key) is Some(prefix) {
          uses.push((prefix, uri))
        }
      }
    }
    for (prefix, uri) in uses {
      let mut current = Some(node)
      let mut internal = false
      while current is Some(ancestor) {
        if ancestor.state().namespaces.iter().any(item => item.0 == prefix) {
          internal = true
          break
        }
        if ancestor.same_node(self) {
          break
        }
        current = ancestor.parent()
      }
      if !internal && !required.iter().any(item => item.0 == prefix) {
        required.push((prefix, uri))
      }
    }
  }
  required
}

///|
fn Element::retain_external_namespaces(self : Element) -> Unit {
  let declarations = self.required_namespaces()
  self.state().namespaces.append(declarations)
}

///|
// libxml emits bindings used by the serialized root before unused inherited ones.
fn Element::serialization_namespaces(self : Element) -> Array[(String, String)] {
  let scope = self.namespace_scope()
  let result = self.state().namespaces.copy()
  let used : Array[String] = []
  if split_name(self.tag()).0 != "" {
    used.push(self.state().prefix.unwrap_or(""))
  }
  for (name, _) in self.state().attributes {
    if self.state().attribute_prefixes.get(name) is Some(prefix) {
      used.push(prefix)
    }
  }
  for prefix in used {
    for binding in scope {
      if binding.0 == prefix && !result.iter().any(item => item.0 == prefix) {
        result.push(binding)
      }
    }
  }
  for binding in scope {
    if !result.iter().any(item => item.0 == binding.0) {
      result.push(binding)
    }
  }
  result
}

///|
fn Element::remove_redundant_namespaces(
  self : Element,
  parent : Element,
) -> Unit {
  let scope = parent.namespace_scope()
  let kept : Array[(String, String)] = []
  for binding in self.state().namespaces.copy() {
    let attribute_use = self
      .iter()
      .any(node => {
        node.state().attributes
        .iter()
        .any(item => {
          split_name(item.0).0 == binding.1 &&
          node.state().attribute_prefixes.get(item.0) == Some(binding.0)
        })
      })
    // String-valued QName content is not typed by this model. Retain its
    // lexical binding rather than rewriting user attribute values.
    let lexical_use = binding.0 != "" &&
      self
      .iter()
      .any(node => {
        node.state().attributes
        .iter()
        .any(item => {
          item.1
          .replace_all(old="\t", new=" ")
          .replace_all(old="\r", new=" ")
          .replace_all(old="\n", new=" ")
          .split(" ")
          .any(token => token.has_prefix(binding.0 + ":"))
        })
      })
    let replacement = scope
      .iter()
      .filter(item => item.1 == binding.1 && (!attribute_use || item.0 != ""))
      .next()
    if replacement is Some(replacement) && !lexical_use {
      for node in self.iter() {
        if split_name(node.tag()).0 == binding.1 &&
          node.state().prefix == Some(binding.0) {
          node.state().prefix = Some(replacement.0)
        }
        for (name, prefix) in node.state().attribute_prefixes.to_array() {
          if prefix == binding.0 && split_name(name).0 == binding.1 {
            node.state().attribute_prefixes[name] = replacement.0
          }
        }
      }
    } else {
      kept.push(binding)
    }
  }
  self.state().namespaces.clear()
  self.state().namespaces.append(kept)
}

///|
fn qualified(
  name : String,
  hint : String?,
  attribute : Bool,
  scope : Map[String, String],
  declarations : Array[(String, String)],
  counter : @ref.Ref[Int32],
) -> String {
  let (uri, local_name) = split_name(name)
  if uri == "" {
    return local_name
  }
  if uri == "http://www.w3.org/XML/1998/namespace" {
    return "xml:\{local_name}"
  }
  if hint is Some(prefix) {
    if (!attribute || prefix != "") && scope.get(prefix) == Some(uri) {
      return if prefix == "" { local_name } else { "\{prefix}:\{local_name}" }
    }
    if (!attribute || prefix != "") && !scope.contains(prefix) {
      scope[prefix] = uri
      declarations.push((prefix, uri))
      return if prefix == "" { local_name } else { "\{prefix}:\{local_name}" }
    }
  }
  for (prefix, value) in declarations {
    if value == uri && (!attribute || prefix != "") {
      return if prefix == "" { local_name } else { "\{prefix}:\{local_name}" }
    }
  }
  // Use the closest declared prefix before allocating a new one.
  let prefixes = scope.keys().to_array()
  prefixes.sort()
  for prefix in prefixes {
    if scope[prefix] == uri && (!attribute || prefix != "") {
      return if prefix == "" { local_name } else { "\{prefix}:\{local_name}" }
    }
  }
  let mut prefix = "ns\{counter.val}"
  while scope.contains(prefix) {
    counter.val += 1
    prefix = "ns\{counter.val}"
  }
  counter.val += 1
  scope[prefix] = uri
  declarations.push((prefix, uri))
  "\{prefix}:\{local_name}"
}

///|
fn serialize_node(
  node : Element,
  out : StringBuilder,
  inherited : Map[String, String],
  counter : @ref.Ref[Int32],
  depth : Int32,
  root_scope : Array[(String, String)]?,
) -> Unit raise JUnitError {
  if depth >= 128 && node.is_element() {
    raise LimitExceeded("XML nesting exceeds 128")
  }
  let state = node.state()
  match state.kind {
    Comment => out.write_string("<!--\{state.value.unwrap_or("")}-->")
    Instruction => {
      let data = state.value.unwrap_or("")
      out.write_string(
        if data == "" {
          "<?\{state.name}?>"
        } else {
          "<?\{state.name} \{data}?>"
        },
      )
    }
    Tag => {
      let scope = inherited.copy()
      let declarations : Array[(String, String)] = []
      for (prefix, uri) in root_scope.unwrap_or(state.namespaces) {
        declarations.push((prefix, uri))
        scope[prefix] = uri
      }
      let name = qualified(
        state.name,
        state.prefix,
        false,
        scope,
        declarations,
        counter,
      )
      let attributes = state.attributes.map(fn(attribute) {
        let (key, value) = attribute
        (
          qualified(
            key,
            state.attribute_prefixes.get(key),
            true,
            scope,
            declarations,
            counter,
          ),
          value,
        )
      })
      out.write_string("<\{name}")
      for (prefix, uri) in declarations {
        let key = if prefix == "" { "xmlns" } else { "xmlns:\{prefix}" }
        out.write_string(" \{key}=\"\{xml_text(uri, attribute=true)}\"")
      }
      for (key, value) in attributes {
        out.write_string(" \{key}=\"\{xml_text(value, attribute=true)}\"")
      }
      if state.children_.is_empty() && state.value is None {
        out.write_string("/>")
      } else {
        out.write_string(">")
        if state.value is Some(text) {
          out.write_string(xml_text(text))
        }
        for id in state.children_ {
          serialize_node(node.handle(id), out, scope, counter, depth + 1, None)
        }
        out.write_string("</\{name}>")
      }
    }
  }
  if state.trailing is Some(tail) {
    out.write_string(xml_text(tail))
  }
}

///|
/// UTF-8 XML content without declaration, including this node's tail.
pub fn Element::to_xml(self : Element) -> String raise JUnitError {
  let out = StringBuilder()
  serialize_node(
    self,
    out,
    Map([]),
    @ref.Ref(0),
    0,
    Some(self.serialization_namespaces()),
  )
  out.to_string()
}

///|
/// Content equality includes attribute order, namespaces and tail. Python's
/// process-randomized hash is deliberately not exposed as a persistent key.
pub fn Element::xml_equal(
  self : Element,
  other : Element,
) -> Bool raise JUnitError {
  self.to_xml() == other.to_xml()
}

///|
/// Content fed to junitparser's process-local Python hash, returned as a
/// portable key. ASCII serialization also escapes non-ASCII comment/PI text.
pub fn Element::comparison_key(self : Element) -> String raise JUnitError {
  let out = StringBuilder()
  for ch in self.to_xml() {
    if ch.to_int() > 127 {
      out.write_string("&#\{ch.to_int()};")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
pub fn Element::repr(self : Element) -> String {
  let attributes = self.attribute_items()
  attributes.sort_by((a, b) => unicode_compare(a.0, b.0))
  let out = StringBuilder()
  out.write_string("<Element '\{self.tag()}'")
  for (key, value) in attributes {
    out.write_string(" \{key}=\"\{value}\"")
  }
  out.write_string(">")
  out.to_string()
}

///|
fn Element::next_descendant(self : Element, anchor : Element) -> Element? {
  if self.state().children_.get(0) is Some(id) {
    return Some(self.handle(id))
  }
  let mut current = self
  while !current.same_node(anchor) {
    if current.following_sibling(None) is Some(sibling) {
      return Some(sibling)
    }
    match current.parent() {
      Some(parent) => current = parent
      None => return None
    }
  }
  None
}

///|
/// Live, depth-first iteration, including this node.
pub fn Element::iter(self : Element) -> Iter[Element] {
  let mut pending = Some(self)
  Iter::new(fn() {
    let result = pending
    if pending is Some(node) {
      pending = node.next_descendant(self)
    }
    result
  })
}

///|
/// Remove all matching direct children using caller-defined typed equality.
pub fn Element::remove_matching(
  self : Element,
  name : String,
  matches : (Element) -> Bool raise,
) -> Unit raise {
  for child in self.iter_children(name=Some(name)) {
    if matches(child) {
      self.remove_node(child)
    }
  }
}

///|
pub fn Element::output(self : Element, name : String) -> String? {
  match self.child(name) {
    Some(node) => node.text()
    None => None
  }
}

///|
/// Update only the first output child, preserving its attributes and children.
pub fn Element::set_output(
  self : Element,
  name : String,
  value : String?,
) -> Unit raise JUnitError {
  match self.child(name) {
    Some(node) => node.set_text(value)
    None => {
      let node = Element::new(name)
      node.set_text(value)
      self.append(node)
    }
  }
}
