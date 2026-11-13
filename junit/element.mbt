///|
// The public type is opaque: mutations go through methods, so callers cannot
// create parent cycles or duplicate a child in the same parent.
struct Element {
  id : Int64
  arena : Arena
}

///|
// Records contain only identifiers, never handles back to their arena. A
// document pool is released when its last handle disappears on every target.
priv struct ElementState {
  kind : NodeKind
  name : String
  attributes : Array[(String, String)]
  namespaces : Array[(String, String)]
  mut defaults : Map[String, Array[(String, String)]]
  mut default_tag : String
  mut doctype : (String, String)?
  mut pre_doctype : Array[String]
  prolog : Array[String]
  epilog : Array[String]
  mut prefix : String?
  attribute_prefixes : Map[String, String]
  mut value : String?
  mut trailing : String?
  children_ : Array[Int64]
  mut parent_ : Int64?
}

///|
// Cross-document moves unite pools by size. Forwarding links form a forest;
// neither node records nor the winning pool point back to a losing pool.
priv struct Arena {
  id : Int64
  nodes : Map[Int64, ElementState]
  mut redirect : Arena?
}

///|
priv enum NodeKind {
  Tag
  Comment
  Instruction
}

///|
let next_element_id : @ref.Ref[Int64] = @ref.Ref(0L)

///|
fn fresh_element_id() -> Int64 raise JUnitError {
  if next_element_id.val == 9223372036854775807L {
    raise LimitExceeded("element identity space exhausted")
  }
  next_element_id.val += 1L
  next_element_id.val
}

///|
fn new_element_state(kind : NodeKind, name : String) -> ElementState {
  {
    kind,
    name,
    attributes: [],
    namespaces: [],
    defaults: Map([]),
    default_tag: name,
    doctype: None,
    pre_doctype: [],
    prolog: [],
    epilog: [],
    prefix: None,
    attribute_prefixes: Map([]),
    value: None,
    trailing: None,
    children_: [],
    parent_: None,
  }
}

///|
fn allocate_element(kind : NodeKind, name : String) -> Element raise JUnitError {
  let id = fresh_element_id()
  let arena = {
    id,
    nodes: Map([(id, new_element_state(kind, name))]),
    redirect: None,
  }
  { id, arena, }
}

///|
fn Arena::root(self : Arena) -> Arena {
  let mut root = self
  let chain = []
  while root.redirect is Some(next) {
    chain.push(root)
    root = next
  }
  for previous in chain {
    previous.redirect = Some(root)
  }
  root
}

///|
fn Element::state(self : Element) -> ElementState {
  self.arena.root().nodes[self.id]
}

///|
fn Element::handle(self : Element, id : Int64) -> Element {
  { id, arena: self.arena.root(), }
}

///|
fn allocate_in(
  arena : Arena,
  kind : NodeKind,
  name : String,
) -> Element raise JUnitError {
  let arena = arena.root()
  let id = fresh_element_id()
  arena.nodes[id] = new_element_state(kind, name)
  { id, arena, }
}

///|
fn join_arenas(a : Arena, b : Arena) -> Unit {
  let a = a.root()
  let b = b.root()
  if a.id == b.id {
    return
  }
  let (large, small) = if a.nodes.length() >= b.nodes.length() {
    (a, b)
  } else {
    (b, a)
  }
  for (id, state) in small.nodes {
    large.nodes[id] = state
  }
  small.nodes.clear()
  small.redirect = Some(large)
}

///|
fn checked_name(name : String) -> String raise JUnitError {
  let (uri, local_name) = if name.has_prefix("{") {
    match name.find("}") {
      Some(end) => (name[1:end].to_owned(), name[end + 1:].to_owned())
      None => raise InvalidValue("invalid expanded XML name")
    }
  } else {
    ("", name)
  }
  if local_name.find(":") != None || local_name == "" {
    raise InvalidValue("use an expanded {namespace}local name")
  }
  let writer = @xml.Writer::new()
  try {
    writer.empty_element(local_name, [])
    if uri != "" {
      checked_text(Some(uri))
    }
  } catch {
    _ => raise InvalidValue("invalid XML name")
  }
  if uri == "" {
    local_name
  } else {
    "{\{uri}}\{local_name}"
  }
}

///|
fn checked_text(text : String?) -> Unit raise JUnitError {
  if text is Some(value) {
    if value.length() > 10000000 {
      raise LimitExceeded("text exceeds 10000000 units")
    }
    let writer = @xml.Writer::new()
    try {
      writer.start_element("value", [])
      writer.text(value)
    } catch {
      _ => raise InvalidValue("invalid XML character")
    }
  }
}

///|
/// Create a mutable XML element. Names use lxml's {namespace}local form.
pub fn Element::new(name : String) -> Element raise JUnitError {
  allocate_element(Tag, checked_name(name))
}

///|
pub fn Element::comment(text : String) -> Element raise JUnitError {
  let writer = @xml.Writer::new()
  writer.comment(text) catch {
    _ => raise InvalidValue("invalid XML comment")
  }
  let node = allocate_element(Comment, "#comment")
  node.state().value = Some(text)
  node
}

///|
pub fn Element::instruction(
  target : String,
  data~ : String = "",
) -> Element raise JUnitError {
  let source = "<?\{target}?>"
  let event = @xml.Reader::from_string(source).read_event() catch {
    _ => raise InvalidValue("invalid processing instruction")
  }
  match event.kind {
    PI(target=parsed_target, data=_) if parsed_target == target => ()
    _ => raise InvalidValue("invalid processing instruction")
  }
  if data.find("?>") != None {
    raise InvalidValue("invalid processing instruction data")
  }
  checked_text(Some(data))
  let node = allocate_element(Instruction, target)
  node.state().value = Some(data)
  node
}

///|
pub fn Element::tag(self : Element) -> String {
  self.state().name
}

///|
pub fn Element::is_element(self : Element) -> Bool {
  self.state().kind is Tag
}

///|
pub fn Element::is_comment(self : Element) -> Bool {
  self.state().kind is Comment
}

///|
pub fn Element::is_instruction(self : Element) -> Bool {
  self.state().kind is Instruction
}

///|
/// Node identity is stable across views and reparenting; it is not XML equality.
pub fn Element::same_node(self : Element, other : Element) -> Bool {
  self.id == other.id
}

///|
pub fn Element::attribute(self : Element, name : String) -> String? {
  for (key, value) in self.state().attributes {
    if key == name {
      return Some(value)
    }
  }
  let state = self.state()
  if state.defaults.get(state.default_tag) is Some(attributes) {
    let (uri, local_name) = split_name(name)
    for (attribute, value) in attributes {
      if attribute == name && attribute.find(":") is None {
        return Some(value)
      }
      if uri != "" && attribute.find(":") is Some(colon) {
        let prefix = attribute[:colon].to_owned()
        let attribute_uri = if prefix == "xml" {
          Some("http://www.w3.org/XML/1998/namespace")
        } else {
          self
          .namespace_scope()
          .iter()
          .filter(item => item.0 == prefix)
          .next()
          .map(item => item.1)
        }
        if attribute[colon + 1:] == local_name && attribute_uri == Some(uri) {
          return Some(value)
        }
      }
    }
  }
  None
}

///|
/// Setting None is a no-op, as with junitparser.Attr. Overwriting keeps order.
pub fn Element::set_attribute(
  self : Element,
  name : String,
  value : String?,
) -> Unit raise JUnitError {
  if value is Some(value) {
    match self.state().kind {
      Tag => ()
      _ => raise InvalidValue("only elements have attributes")
    }
    let name = checked_name(name)
    checked_text(Some(value))
    for i = 0; i < self.state().attributes.length(); i = i + 1 {
      if self.state().attributes[i].0 == name {
        self.state().attributes[i] = (name, value)
        return
      }
    }
    self.state().attributes.push((name, value))
  }
}

///|
pub fn Element::delete_attribute(self : Element, name : String) -> Unit {
  for i = 0; i < self.state().attributes.length(); i = i + 1 {
    if self.state().attributes[i].0 == name {
      ignore(self.state().attributes.remove(i))
      return
    }
  }
}

///|
/// Return a snapshot of attributes in insertion order.
pub fn Element::attribute_items(self : Element) -> Array[(String, String)] {
  self.state().attributes.copy()
}

///|
pub fn Element::int_attribute(
  self : Element,
  name : String,
) -> @bigint.BigInt? raise JUnitError {
  match self.attribute(name) {
    None | Some("") => None
    Some(value) => Some(py_int(value))
  }
}

///|
pub fn Element::float_attribute(
  self : Element,
  name : String,
) -> Double? raise JUnitError {
  py_float_attr(self.attribute(name))
}

///|
pub fn Element::set_int_attribute(
  self : Element,
  name : String,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  let text = value.to_string()
  if text.length() - (if text.has_prefix("-") { 1 } else { 0 }) > 4300 {
    raise InvalidValue("integer exceeds 4300 decimal digits")
  }
  self.set_attribute(name, Some(text))
}

///|
pub fn Element::set_float_attribute(
  self : Element,
  name : String,
  value : Double,
) -> Unit raise JUnitError {
  self.set_attribute(name, Some(py_repr(value)))
}

///|
/// Custom typed fields use caller-defined conversion without an XML engine fork.
pub fn[T] Element::read_attribute(
  self : Element,
  name : String,
  decode : (String) -> T raise,
) -> T? raise {
  match self.attribute(name) {
    None => None
    Some(value) => Some(decode(value))
  }
}

///|
pub fn[T] Element::write_attribute(
  self : Element,
  name : String,
  value : T,
  encode : (T) -> String raise,
) -> Unit raise {
  self.set_attribute(name, Some(encode(value)))
}

///|
pub fn Element::text(self : Element) -> String? {
  self.state().value
}

///|
pub fn Element::set_text(
  self : Element,
  text : String?,
) -> Unit raise JUnitError {
  checked_text(text)
  match self.state().kind {
    Comment => {
      let writer = @xml.Writer::new()
      writer.comment(text.unwrap_or("")) catch {
        _ => raise InvalidValue("invalid XML comment")
      }
    }
    Instruction =>
      if text.unwrap_or("").find("?>") != None {
        raise InvalidValue("invalid processing instruction data")
      }
    Tag => ()
  }
  self.state().value = text
}

///|
pub fn Element::tail(self : Element) -> String? {
  self.state().trailing
}

///|
pub fn Element::set_tail(
  self : Element,
  text : String?,
) -> Unit raise JUnitError {
  checked_text(text)
  self.state().trailing = text
}

///|
pub fn Element::parent(self : Element) -> Element? {
  self.state().parent_.map(id => self.handle(id))
}

///|
/// Snapshot of direct children. The returned handles still share their nodes.
pub fn Element::children(
  self : Element,
  name~ : String? = None,
) -> Array[Element] {
  self.state().children_
  .iter()
  .map(id => self.handle(id))
  .filter(child => {
    name == None ||
    (child.state().kind is Tag && name == Some(child.state().name))
  })
  .to_array()
}

///|
pub fn Element::child(self : Element, name : String) -> Element? {
  for id in self.state().children_ {
    let child = self.handle(id)
    if child.state().kind is Tag && child.state().name == name {
      return Some(child)
    }
  }
  None
}

///|
fn Element::following_sibling(self : Element, name : String?) -> Element? {
  if self.parent() is Some(parent) {
    let mut found = false
    for id in parent.state().children_ {
      let sibling = self.handle(id)
      if found &&
        (
          name == None ||
          (sibling.state().kind is Tag && name == Some(sibling.state().name))
        ) {
        return Some(sibling)
      }
      if id == self.id {
        found = true
      }
    }
  }
  None
}

///|
/// Live iteration prefetches the next matching sibling before yielding.
/// Moving or removing a prefetched node does not turn this into a snapshot.
pub fn Element::iter_children(
  self : Element,
  name~ : String? = None,
) -> Iter[Element] {
  let mut started = false
  let mut pending : Element? = None
  Iter::new(fn() {
    if !started {
      started = true
      for id in self.state().children_ {
        let child = self.handle(id)
        if name == None ||
          (child.state().kind is Tag && name == Some(child.state().name)) {
          pending = Some(child)
          break
        }
      }
    }
    let result = pending
    if pending is Some(node) {
      pending = node.following_sibling(name)
    }
    result
  })
}

///|
fn Element::detach(self : Element) -> Unit {
  if self.parent() is Some(parent) {
    let children = parent.state().children_
    for i = 0; i < children.length(); i = i + 1 {
      if children[i] == self.id {
        ignore(children.remove(i))
        break
      }
    }
    self.state().parent_ = None
  }
}

///|
fn Element::check_insertion(
  self : Element,
  child : Element,
) -> Unit raise JUnitError {
  match self.state().kind {
    Tag => ()
    _ => raise InvalidValue("only elements can have children")
  }
  let mut ancestor = Some(self)
  while ancestor is Some(current) {
    if current.id == child.id {
      raise InvalidValue("cannot append an ancestor")
    }
    ancestor = current.parent()
  }
}

///|
/// Append moves an attached node, including its tail, as lxml does.
pub fn Element::append(
  self : Element,
  child : Element,
) -> Unit raise JUnitError {
  self.check_insertion(child)
  child.retain_external_namespaces()
  child.remove_redundant_namespaces(self)
  join_arenas(self.arena, child.arena)
  child.detach()
  self.state().children_.push(child.id)
  child.state().parent_ = Some(self.id)
  child.state().prolog.clear()
  child.state().epilog.clear()
  child.adopt_document(
    self.state().defaults,
    self.state().doctype,
    self.state().pre_doctype,
  )
}

///|
pub fn Element::append_all(
  self : Element,
  children : Array[Element],
) -> Unit raise JUnitError {
  for child in children {
    self.append(child)
  }
}

///|
/// Resolve the reference sibling before moving an existing child.
pub fn Element::insert(
  self : Element,
  index : Int32,
  child : Element,
) -> Unit raise JUnitError {
  self.check_insertion(child)
  let length = self.state().children_.length()
  let position = if index < 0 {
    if index < -length {
      length
    } else {
      length + index
    }
  } else {
    index.min(length)
  }
  let reference = self.state().children_.get(position)
  if reference == Some(child.id) {
    child.remove_redundant_namespaces(self)
    return
  }
  child.retain_external_namespaces()
  child.remove_redundant_namespaces(self)
  join_arenas(self.arena, child.arena)
  child.detach()
  let children = self.state().children_
  let mut destination = children.length()
  if reference is Some(reference) {
    for i = 0; i < children.length(); i = i + 1 {
      if children[i] == reference {
        destination = i
        break
      }
    }
  }
  children.insert(destination, child.id)
  child.state().parent_ = Some(self.id)
  child.state().prolog.clear()
  child.state().epilog.clear()
  child.adopt_document(
    self.state().defaults,
    self.state().doctype,
    self.state().pre_doctype,
  )
}

///|
fn Element::adopt_document(
  self : Element,
  defaults : Map[String, Array[(String, String)]],
  doctype : (String, String)?,
  pre_doctype : Array[String],
) -> Unit {
  let pending = [self.id]
  while pending.pop() is Some(id) {
    let node = self.handle(id)
    node.state().prolog.clear()
    node.state().epilog.clear()
    node.state().defaults = defaults
    node.state().doctype = doctype
    node.state().pre_doctype = pre_doctype
    for child in node.state().children_ {
      pending.push(child)
    }
  }
}

///|
/// Remove a direct child by node identity, retaining the child's tail.
pub fn Element::remove_node(
  self : Element,
  child : Element,
) -> Unit raise JUnitError {
  if child.state().parent_ == Some(self.id) {
    child.detach()
  } else {
    raise InvalidValue("node is not a child")
  }
}

///|
/// Deep copy; no descendants or attributes are shared with the source.
pub fn Element::clone(self : Element) -> Element raise JUnitError {
  fn copy_fields(source : Element, target : Element) -> Unit {
    for attribute in source.state().attributes {
      target.state().attributes.push(attribute)
    }
    for ns in source.state().namespaces {
      target.state().namespaces.push(ns)
    }
    target.state().default_tag = source.state().default_tag
    for (key, value) in source.state().attribute_prefixes {
      target.state().attribute_prefixes[key] = value
    }
    target.state().prefix = source.state().prefix
    target.state().value = source.state().value
    target.state().trailing = source.state().trailing
  }
  let root = allocate_element(self.state().kind, self.state().name)
  copy_fields(self, root)
  for declaration in self.required_namespaces() {
    root.state().namespaces.push(declaration)
  }
  let pending = [(self, root)]
  while pending.pop() is Some((source, target)) {
    for id in source.state().children_ {
      let child = source.handle(id)
      let copied = allocate_in(
        root.arena,
        child.state().kind,
        child.state().name,
      )
      copy_fields(child, copied)
      target.state().children_.push(copied.id)
      copied.state().parent_ = Some(target.id)
      pending.push((child, copied))
    }
  }
  root
}
