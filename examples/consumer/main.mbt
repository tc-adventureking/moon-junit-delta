///|
fn main raise {
  let baseline = @delta.parse_report(
    "<testsuite><testcase classname='api' name='login'/></testsuite>",
  )
  let current = @delta.parse_report(
    "<testsuite><testcase classname='api' name='login'><failure message='HTTP 500'/></testcase></testsuite>",
  )
  let diff = @delta.compare([baseline], current)
  println(diff.to_text())
}

///|
test "external consumer uses public API and gate semantics" {
  let a = @delta.parse_report(
    "<testsuite><testcase classname='C' name='x'/></testsuite>",
  )
  let b = @delta.parse_report(
    "<testsuite><testcase classname='C' name='x'><failure/></testcase></testsuite>",
  )
  let r = @delta.compare([a], b)
  assert_eq(r.exit_code(), 1)
  assert_eq(r.entries[0].category, "new_failure")
  assert_true(r.to_json_string().contains("new_failure"))
  assert_true(r.to_markdown().contains("FAIL"))
  assert_eq(@delta.parse_duration("1.1234569"), Some(1123456L))
}

///|
test "external consumer can inspect raw duplicates and normalize retries" {
  let xml = "<testsuite><testcase name='x'><failure/></testcase><testcase name='x'/></testsuite>"
  let raw = @delta.parse_document(xml)
  assert_eq(raw.cases.length(), 2)
  assert_true(raw.cases[0].is_failure())
  assert_true(raw.cases[1].is_passed())
  let normalized = @delta.parse_report(xml, duplicates=@delta.Attempts)
  assert_eq(normalized.cases.length(), 1)
  assert_true(normalized.cases[0].flaky)
  assert_eq(normalized.cases[0].attempts, 2)
}
