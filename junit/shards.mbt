///|
// The key is scoped to the destination parent. Length prefixes distinguish
// absent, empty and arbitrary user strings without reserved delimiters.
fn shard_key(suite : Element) -> String? raise JUnitError {
  let properties = suite.properties().to_array()
  if properties.length() > 1 && properties.iter().any(p => p.name() == None) {
    // junitparser cannot order this property list. Keep the suite separate.
    return None
  }
  let key = StringBuilder()
  fn field(value : String?) -> Unit {
    match value {
      None => key.write_string("-")
      Some(s) => {
        key.write_string(s.length().to_string())
        key.write_char(':')
        key.write_string(s)
      }
    }
  }
  for attr in ["name", "hostname", "timestamp"] {
    field(suite.attribute(attr))
  }
  for property in sorted_properties(properties, false) {
    field(property.name())
    field(property.value())
  }
  Some(key.to_string())
}

///|
priv struct ShardMerge {
  suites : Map[(Int64, String), Element]
  mut suite_count : Int32
  mut case_count : Int32
}

///|
fn ShardMerge::add_child(
  self : ShardMerge,
  parent : Element,
  child : Element,
  depth : Int32,
  keep_metadata~ : Bool,
) -> Unit raise JUnitError {
  if child.is_element() && child.tag() == "testsuite" {
    self.suite_count += 1
    if self.suite_count > 1000000 || depth > 128 {
      raise LimitExceeded(
        "shard merge exceeds 1000000 suites or 128 suite levels",
      )
    }
    let key = shard_key(child).map(identity => (parent.id, identity))
    let existing = key.bind(k => self.suites.get(k))
    let suite = match existing {
      Some(suite) => suite
      None => {
        let suite = child.clone_shell()
        parent.append(suite)
        if key is Some(k) {
          self.suites[k] = suite
        }
        suite
      }
    }
    for nested in child.iter_children() {
      self.add_child(suite, nested, depth + 1, keep_metadata=existing is None)
    }
  } else if child.is_element() && child.tag() == "testcase" {
    self.case_count += 1
    if self.case_count > 1000000 {
      raise LimitExceeded("shard merge exceeds 1000000 cases")
    }
    parent.append(child.clone())
  } else if keep_metadata {
    parent.append(child.clone())
  }
}

///|
/// Merge parsed shards into a fresh report. Inputs may repeat or share nodes.
pub fn merge_shards(
  inputs : Iter[JUnitXml],
  flavor~ : Flavor = Base,
) -> JUnitXml raise {
  merge_shards_from(inputs, report => report, flavor~)
}

///|
/// Load and merge one source at a time. Equal suites coalesce only under
/// the same parent. Read or validation failures leave all source trees intact.
pub fn[T] merge_shards_from(
  sources : Iter[T],
  read : (T) -> JUnitXml raise,
  flavor~ : Flavor = Base,
) -> JUnitXml raise {
  let result = JUnitXml::new(flavor~)
  let merge : ShardMerge = { suites: Map([]), suite_count: 0, case_count: 0, }
  for source in sources {
    let root = read(source).element()
    if root.is_element() && root.tag() == "testsuite" {
      merge.add_child(result.element(), root, 1, keep_metadata=false)
    } else if root.is_element() && root.tag() == "testsuites" {
      for child in root.iter_children() {
        merge.add_child(result.element(), child, 1, keep_metadata=false)
      }
    } else {
      raise InvalidFormat("expected testsuite or testsuites")
    }
  }
  fn update_nested(suite : TestSuite) -> Unit raise JUnitError {
    for child in suite.suites() {
      update_nested(child)
      child.update_statistics()
    }
  }
  for suite in result.suites() {
    update_nested(suite)
  }
  result.update_statistics_with_root_cases()
  result
}
