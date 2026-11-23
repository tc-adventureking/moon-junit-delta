///|
fn main raise {
  let suite = @junit.TestSuite::new(name=Some("service"))
  let case = @junit.TestCase::new(
    name=Some("login"),
    classname=Some("api"),
    time=Some(0.12),
  )
  suite.add_case(case)
  suite.add_property("build", "12")
  let report = @junit.JUnitXml::new()
  report.add_suite(suite)
  case.set_results([@junit.TestResult::new(Failure, message=Some("assertion"))])
  report.update_statistics()
  println(report.element().to_xml())

  let edited = @junit.JUnitXml::from_string(
    "<testsuite name='s'><properties><property name='old' value='1'/></properties><testcase name='keep' time='0.1'><system-out>log</system-out><extra xmlns='urn:x'>payload</extra></testcase><testcase name='remove'/></testsuite>",
  )
  let changed = edited.suites().next().unwrap()
  changed.remove_case(changed.cases().to_array()[1])
  changed.add_property("new", "2")
  changed.cases().next().unwrap().set_classname(Some("renamed"))
  edited.update_statistics()
  println(edited.element().to_xml())

  let left = @junit.JUnitXml::from_string(
    "<testsuite name='s'><testcase name='one' time='0.1'/></testsuite>",
  )
  let right = @junit.JUnitXml::from_string(
    "<testsuite name='s'><testcase name='two' time='0.2'><failure/><failure/></testcase></testsuite>",
  )
  let merged = left.merged(right)
  println(merged.element().to_xml())

  let retries = @junit.JUnitXml::from_string(
    "<testsuite name='retry'><testcase name='a' group='g'><rerunFailure message='retry'><stackTrace>trace</stackTrace></rerunFailure></testcase></testsuite>",
    flavor=XUnit2,
  )
  let rerun = retries.suites().next().unwrap().cases().next().unwrap()
  assert_true(rerun.is_rerun() && rerun.is_passed())
  assert_eq(rerun.rerun_failures()[0].stack_trace(), Some("trace"))
  rerun.add_property("attempt", "2")
  retries.update_statistics()
  println(retries.element().to_xml())
}
