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
