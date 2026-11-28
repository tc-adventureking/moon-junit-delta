///|
test "mutable child views and lxml reparenting" {
  let first = Element::new("suite")
  let second = Element::new("suite")
  let case = Element::new("case")
  case.set_tail(Some("tail"))
  first.append(case)
  let view = first.children()[0]
  view.set_attribute("name", Some("live"))
  assert_eq(case.attribute("name"), Some("live"))
  second.append(case)
  assert_eq(first.children().length(), 0)
  assert_eq(second.children().length(), 1)
  assert_true(case.parent().unwrap().same_node(second))
  second.append(case)
  assert_eq(second.children().length(), 1)
  assert_eq(case.tail(), Some("tail"))
}

///|
test "insert reference is resolved before detach and copies are isolated" {
  let root = Element::new("root")
  let a = Element::new("a")
  let b = Element::new("b")
  let c = Element::new("c")
  root.append_all([a, b, c])
  root.insert(2, a)
  assert_eq(root.children().map(child => child.tag()), ["b", "a", "c"])
  root.insert(0, b)
  assert_eq(root.children().map(child => child.tag()), ["b", "a", "c"])
  let copied = root.clone()
  copied.child("a").unwrap().set_text(Some("copy"))
  assert_eq(a.text(), None)
  assert_false(copied.child("a").unwrap().same_node(a))
  a.set_tail(Some("retained"))
  root.remove_node(a)
  assert_eq(a.tail(), Some("retained"))
  assert_true(a.parent() is None)
}

///|
test "cycle rejection leaves existing tree intact" {
  let root = Element::new("root")
  let child = Element::new("child")
  root.append(child)
  assert_true(
    try {
      child.append(root)
      false
    } catch {
      InvalidValue(_) => true
      _ => false
    },
  )
  assert_true(root.parent() is None)
  assert_true(root.children()[0].same_node(child))
  assert_eq(child.children().length(), 0)
}

///|
test "ordered typed attributes and custom converters" {
  let element = Element::new("{urn:custom}node")
  element.set_attribute("a", Some("first"))
  element.set_attribute("b", Some("second"))
  element.set_attribute("a", Some("updated"))
  element.set_attribute("a", None)
  assert_eq(element.attribute_items(), [("a", "updated"), ("b", "second")])
  element.set_attribute("amount", Some("123456789012345678901234567890"))
  assert_eq(
    element.int_attribute("amount").unwrap().to_string(),
    "123456789012345678901234567890",
  )
  element.set_attribute("time", Some("1,2,3"))
  assert_eq(element.float_attribute("time"), Some(123.0))
  element.write_attribute("enabled", true, value => {
    if value {
      "yes"
    } else {
      "no"
    }
  })
  assert_eq(
    element.read_attribute("enabled", value => value == "yes"),
    Some(true),
  )
  assert_true(
    try {
      element.set_text(Some("\u0000"))
      false
    } catch {
      InvalidValue(_) => true
      _ => false
    },
  )
  assert_eq(element.text(), None)
}

///|
test "live iteration matches lxml after removing a prefetched sibling" {
  let root = Element::new("root")
  let a = Element::new("a")
  let b = Element::new("b")
  let c = Element::new("c")
  root.append_all([a, b, c])
  let iter = root.iter_children()
  assert_eq(iter.next().unwrap().tag(), "a")
  root.remove_node(b)
  assert_eq(iter.to_array().map(node => node.tag()), ["b"])
  let iter = root.iter_children()
  assert_eq(iter.next().unwrap().tag(), "a")
  root.remove_node(a)
  assert_eq(iter.to_array().map(node => node.tag()), ["c"])
}

///|
test "comments and instructions keep tails and validate setters" {
  let root = Element::new("root")
  let comment = Element::comment("note")
  let pi = Element::instruction("testcase", data=" leading ")
  pi.set_tail(Some("tail"))
  root.append_all([comment, pi])
  assert_eq(root.children().length(), 2)
  assert_true(root.child("testcase") is None)
  assert_true(pi.is_instruction())
  assert_true(comment.is_comment())
  assert_eq(pi.text(), Some(" leading "))
  assert_true(
    try {
      comment.set_text(Some("bad--comment"))
      false
    } catch {
      InvalidValue(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      pi.set_text(Some("bad?>"))
      false
    } catch {
      InvalidValue(_) => true
      _ => false
    },
  )
  assert_eq(pi.tail(), Some("tail"))
}
