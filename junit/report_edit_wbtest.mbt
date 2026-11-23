///|
test "root statistics explicitly include direct cases and preserve default semantics" {
  let report = JUnitXml::from_decoded(
    "<testsuites><testcase name='top'><failure/></testcase><testsuite><testcase name='nested'/></testsuite></testsuites>",
  )
  report.update_statistics()
  assert_eq(report.tests().unwrap().to_string(), "1")
  assert_eq(report.failures().unwrap().to_string(), "0")
  report.update_statistics_with_root_cases()
  assert_eq(report.tests().unwrap().to_string(), "2")
  assert_eq(report.failures().unwrap().to_string(), "1")
  report.update_statistics()
  assert_eq(report.tests().unwrap().to_string(), "1")
}

///|
test "removing a nested suite updates report counts and XML" {
  let report = JUnitXml::from_decoded(
    "<testsuites><testsuite name='parent'><testcase name='keep'/><testsuite name='child'><testcase name='drop'><failure/></testcase></testsuite></testsuite></testsuites>",
  )
  report.update_statistics()
  assert_eq(report.tests().unwrap().to_string(), "2")
  assert_eq(report.failures().unwrap().to_string(), "1")
  let parent = report.suites().next().unwrap()
  let child = parent.suites().next().unwrap()
  parent.element().remove_node(child.element())
  report.update_statistics()
  let restored = JUnitXml::from_decoded(report.element().write_xml())
  assert_eq(restored.tests().unwrap().to_string(), "1")
  assert_eq(restored.failures().unwrap().to_string(), "0")
  assert_true(restored.suites().next().unwrap().suites().next() is None)
}

///|
test "editing a shared testcase survives pretty XML round trip" {
  let case = TestCase::new(name=Some("login"), time=Some(0.12))
  let suite = TestSuite::new(name=Some("service"))
  suite.add_case(case)
  let report = JUnitXml::new()
  report.add_suite(suite)
  case.set_results([TestResult::new(Failure, message=Some("timeout"))])
  report.update_statistics()
  let restored = JUnitXml::from_decoded(report.element().write_xml(pretty=true))
  assert_eq(restored.tests().unwrap().to_string(), "1")
  assert_eq(restored.failures().unwrap().to_string(), "1")
  assert_false(
    restored.suites().next().unwrap().cases().next().unwrap().is_passed(),
  )
}

///|
test "live filtered iterators follow prefetched nodes after insertion and reparenting" {
  let root = Element::from_string(
    "<r><item id='a'/><other/><item id='b'/><item id='c'/></r>",
  )
  let iter = root.iter_children(name=Some("item"))
  assert_eq(iter.next().unwrap().attribute("id"), Some("a"))
  root.insert(0, Element::new("item"))
  assert_eq(iter.next().unwrap().attribute("id"), Some("b"))
  let dest = Element::from_string("<r><other/></r>")
  dest.append(root.children(name=Some("item")).last().unwrap())
  dest.append(Element::from_string("<item id='d'/>"))
  assert_eq(iter.next().unwrap().attribute("id"), Some("c"))
  assert_eq(iter.next().unwrap().attribute("id"), Some("d"))
  assert_true(iter.next() is None)
}

///|
test "shards retain nested identities, sibling order, extensions and input ownership" {
  let left = JUnitXml::from_decoded(
    "<testsuites><testsuite name='parent'><testsuite name='child' tests='99'><testcase name='left' time='1'/><x:extra xmlns:x='urn:x'/></testsuite></testsuite></testsuites>",
  )
  let shard = JUnitXml::from_decoded(
    "<testsuites><testcase name='top'/><testsuite name='parent'><testsuite name='child' tests='42'><testcase name='right' time='2'><failure/></testcase><x:extra xmlns:x='urn:x'/></testsuite><testcase name='last'/></testsuite></testsuites>",
  )
  let original = shard.element().to_xml()
  let report = merge_shards([left, shard].iter())
  let parent = report.suites().next().unwrap()
  let child = parent.suites().next().unwrap()
  assert_eq(report.tests().unwrap().to_string(), "4")
  assert_eq(report.failures().unwrap().to_string(), "1")
  assert_eq(child.tests().unwrap().to_string(), "2")
  assert_eq(child.time(), Some(3.0))
  assert_eq(child.element().children().map(e => e.tag()), [
    "testcase", "{urn:x}extra", "testcase",
  ])
  assert_eq(parent.element().children().map(e => e.tag()), [
    "testsuite", "testcase",
  ])
  assert_eq(shard.element().to_xml(), original)
  let doubled = merge_shards([report, report].iter())
  assert_eq(doubled.tests().unwrap().to_string(), "8")
  assert_eq(doubled.failures().unwrap().to_string(), "2")
  assert_eq(report.tests().unwrap().to_string(), "4")
}

///|
test "shard keys agree with suite equality and retain unorderable property lists" {
  let forms = [
    "<testsuite/>", "<testsuite name=''/>", "<testsuite name='a:b'/>", "<testsuite name='a' hostname=':b'/>",
    "<testsuite timestamp='-'/>", "<testsuite><properties><property name='p' value='1'/><property name='p'/></properties></testsuite>",
    "<testsuite><properties><property name='p'/><property name='p' value='1'/></properties></testsuite>",
    "<testsuite><properties><property name='a'/><property name='b'/></properties></testsuite>",
    "<testsuite><properties><property name='b'/><property name='a'/></properties></testsuite>",
    "<testsuite><properties><property/></properties></testsuite>",
  ].map(s => TestSuite::from_string(s))
  for left in forms {
    for right in forms {
      assert_eq(
        shard_key(left.element()) == shard_key(right.element()),
        left.equal(right),
      )
    }
  }
  let malformed = JUnitXml::from_decoded(
    "<testsuite><properties><property/><property name='a'/></properties><testcase/></testsuite>",
  )
  let separate = merge_shards([malformed, malformed].iter())
  assert_eq(separate.len(), 2)
  assert_eq(separate.tests().unwrap().to_string(), "2")
}

///|
test "shard statistics honor xunit2, input ordering and fractional times" {
  let xml = "<testsuites><testsuite name='s'><testsuite name='n'><testcase time='0.0004'/></testsuite><testcase time='0.0004'/><testsuite name='n'><testcase time='0.0004'><skipped/></testcase></testsuite></testsuite><testcase name='top'/></testsuites>"
  let source = JUnitXml::from_string(xml, flavor=XUnit2)
  let before = source.element().to_xml()
  let merged = merge_shards([source].iter(), flavor=XUnit2)
  assert_eq(merged.element().children().map(e => e.tag()), [
    "testsuite", "testcase",
  ])
  assert_eq(merged.element().attribute("skipped"), None)
  let suite = merged.suites().next().unwrap()
  assert_eq(suite.suites().count(), 1)
  assert_eq(suite.time(), Some(0.001))
  let nested = suite.suites().next().unwrap()
  assert_eq(nested.tests().unwrap().to_string(), "2")
  assert_eq(nested.skipped().unwrap().to_string(), "1")
  let stats = merged.element().to_xml()
  nested.update_statistics()
  suite.update_statistics()
  assert_eq(merged.element().to_xml(), stats)
  suite.set_name(Some("changed"))
  assert_eq(source.element().to_xml(), before)
}

///|
test "shards make DTD defaults explicit and preserve lexical namespace bindings" {
  let source = JUnitXml::from_decoded(
    "<!DOCTYPE testsuites [<!ATTLIST testsuite name CDATA 'default-suite'><!ATTLIST testcase name CDATA 'default-case' time CDATA '1.5' p:kind CDATA 'p:Type'>]><testsuites xmlns:p='urn:test'><testsuite><testcase/><testcase name='override' time='2'/></testsuite></testsuites>",
  )
  let other = JUnitXml::from_string(
    "<testsuites xmlns:p='urn:other'><testsuite name='default-suite'><testcase name='third' kind='p:Type'><system-out>p:Text</system-out></testcase></testsuite></testsuites>",
  )
  let original = source.element().to_xml()
  let merged = merge_shards([source, other].iter())
  let saved = JUnitXml::from_decoded(merged.element().write_xml())
  let suite = saved.suites().next().unwrap()
  assert_eq(suite.name(), Some("default-suite"))
  let cases = suite.cases().to_array()
  assert_eq(cases.map(c => c.name()), [
    Some("default-case"),
    Some("override"),
    Some("third"),
  ])
  assert_eq(suite.time(), Some(3.5))
  assert_eq(cases[0].element().attribute("{urn:test}kind"), Some("p:Type"))
  assert_true(cases[2].element().namespace_scope().contains(("p", "urn:other")))
  assert_eq(source.element().to_xml(), original)
}

///|
test "raw suite roots are accepted and a failed loader stops at the offending shard" {
  let raw = JUnitXml::from_element(
    Element::from_string(
      "<testsuite name='raw'><testcase name='one'/></testsuite>",
    ),
  )
  let before = raw.element().to_xml()
  let merged = merge_shards([raw].iter())
  assert_eq(merged.suites().next().unwrap().name(), Some("raw"))
  assert_eq(merged.tests().unwrap().to_string(), "1")
  let reads : Array[Int32] = []
  try {
    ignore(
      merge_shards_from([0, 1, 2].iter(), i => {
        reads.push(i)
        if i == 1 {
          raise InvalidFormat("invalid source")
        }
        raw
      }),
    )
    fail("expected loader failure")
  } catch {
    InvalidFormat("invalid source") => ()
    e => raise e
  }
  assert_eq(reads, [0, 1])
  assert_eq(raw.element().to_xml(), before)
}
