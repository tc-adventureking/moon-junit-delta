///|
/// Scope components are interned once, never repeated as full JSON map keys.
priv struct Scope {
  kind : Int32
  parent : Int32
  component : String
  path : ReadOnlyArray[String]
  encoded_path : ReadOnlyArray[String]
  json_body : Int64
  md_body : Int64
  text_body : Int64
}

///|
priv struct ScopePool {
  scopes : Array[Scope]
  indexes : Map[(Int32, String), Int32]
}

///|
fn new_scope_pool() -> ScopePool {
  {
    scopes: [
      {
        kind: 1,
        parent: -2,
        component: "",
        path: [],
        encoded_path: [],
        json_body: 0L,
        md_body: 0L,
        text_body: 0L,
      },
    ],
    indexes: Map([]),
  }
}

///|
fn ScopePool::intern(
  self : ScopePool,
  parent : Int32,
  component : String,
) -> Int32 {
  let key = (parent, component)
  if self.indexes.get(key) is Some(index) {
    return index
  }
  let path : Array[String] = []
  let encoded : Array[String] = []
  if parent >= 0 {
    for part in self.scopes[parent].path {
      path.push(part)
    }
    for part in self.scopes[parent].encoded_path {
      encoded.push(part)
    }
  }
  path.push(component)
  let encoded_component = Json(component).stringify()
  encoded.push(encoded_component)
  let previous = if parent > 0 { Some(self.scopes[parent]) } else { None }
  let index = self.scopes.length()
  self.scopes.push({
    kind: if parent < 0 {
      0
    } else {
      1
    },
    parent,
    component,
    path: ReadOnlyArray::from_array(path),
    encoded_path: ReadOnlyArray::from_array(encoded),
    json_body: previous.map(s => s.json_body + 1L).unwrap_or(0L) +
    encoded_component.length().to_int64(),
    md_body: previous.map(s => s.md_body + 1L).unwrap_or(0L) +
    safe_units(encoded_component),
    text_body: previous.map(s => s.text_body + 1L).unwrap_or(0L) +
    terminal_units(encoded_component),
  })
  self.indexes[key] = index
  index
}

///|
fn ScopePool::remap(
  self : ScopePool,
  scopes : ReadOnlyArray[Scope],
) -> Array[Int32] {
  let mapping : Array[Int32] = [0]
  for i = 1; i < scopes.length(); i = i + 1 {
    let scope = scopes[i]
    let parent = if scope.kind == 0 { -1 } else { mapping[scope.parent] }
    mapping.push(self.intern(parent, scope.component))
  }
  mapping
}

///|
fn compare_scope(a : Scope, b : Scope) -> Int32 {
  if a.kind != b.kind {
    return a.kind.compare(b.kind)
  }
  let common = if a.encoded_path.length() < b.encoded_path.length() {
    a.encoded_path.length()
  } else {
    b.encoded_path.length()
  }
  for i = 0; i < common; i = i + 1 {
    let x = a.encoded_path[i]
    let y = b.encoded_path[i]
    if !physical_equal(x, y) {
      let order = x.lexical_compare(y)
      if order != 0 {
        return order
      }
    }
  }
  // In JSON arrays a comma precedes a closing bracket: longer prefixes first.
  b.encoded_path.length().compare(a.encoded_path.length())
}

///|
fn ScopePool::ranks(self : ScopePool) -> Array[Int32] {
  let order : Array[Int32] = []
  for i = 0; i < self.scopes.length(); i = i + 1 {
    order.push(i)
  }
  order.sort_by((a, b) => compare_scope(self.scopes[a], self.scopes[b]))
  let ranks = Array::make(self.scopes.length(), 0)
  for i = 0; i < order.length(); i = i + 1 {
    ranks[order[i]] = i
  }
  ranks
}

///|
fn Scope::id_units(
  self : Scope,
  encoded_name : String,
  format : Int32,
) -> Int64 {
  let prefix = if self.kind == 0 { "[\"class\"," } else { "[\"suite\",[" }
  let suffix = if self.kind == 0 { "," } else { "]," }
  match format {
    1 =>
      safe_units(prefix) +
      self.md_body +
      safe_units(suffix) +
      safe_units(encoded_name) +
      safe_units("]")
    2 =>
      terminal_units(prefix) +
      self.text_body +
      terminal_units(suffix) +
      terminal_units(encoded_name) +
      1L
    _ =>
      prefix.length().to_int64() +
      self.json_body +
      suffix.length().to_int64() +
      encoded_name.length().to_int64() +
      1L
  }
}
