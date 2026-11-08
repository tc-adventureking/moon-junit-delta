///|
fn rejects(xml : String) -> Bool {
  try {
    ignore(parse_report(xml))
    false
  } catch {
    _ => true
  }
}

///|
test "XML reuse probe declaration BOM entities CDATA comments Chinese" {
  let xml = "\u{FEFF}<?xml version='1.0' encoding='UTF-8'?><testsuite name='中文'><!--comment--><testcase classname='' name='&lt;&#x41;&amp;' time='0.123456789'><failure message='bad'><![CDATA[x < y]]></failure></testcase><testcase name='好'/></testsuite>"
  let r = parse_report(xml)
  assert_eq(r.cases.length(), 2)
  assert_eq(r.cases[0].id.key(), "[\"class\",\"\",\"<A&\"]")
  assert_eq(r.cases[0].time_us, Some(123456L))
  assert_eq(r.cases[0].message, "badx < y")
  assert_eq(r.cases[1].id.key(), "[\"suite\",[\"中文\"],\"好\"]")
}

///|
test "XML attribute normalization preserves referenced whitespace" {
  let r = parse_report("<testsuite><testcase classname='a\tb\nc' name='x&#10;y'/></testsuite>")
  assert_eq(r.cases[0].id.key(), "[\"class\",\"a b c\",\"x\\ny\"]")
}

///|
test "identity is exact tagged and includes full fallback path" {
  let r = parse_report("<testsuites><testsuite name='a'><testsuite name='b'><testcase name='x'/><testcase classname='a/b' name='x'/><testcase classname='a/b' name=' x'/><testcase classname='' name='x'/></testsuite></testsuite></testsuites>")
  assert_eq(r.cases.length(), 4)
  assert_eq(r.cases[0].id.key(), "[\"suite\",[\"a\",\"b\"],\"x\"]")
}

///|
test "duplicate policy requires explicit attempts and preserves final failure" {
  let xml = "<testsuite><testcase name='x'/><testcase name='x'><failure/></testcase></testsuite>"
  assert_true(rejects(xml))
  let r = parse_report(xml, duplicates=Attempts)
  assert_eq(r.cases.length(), 1)
  assert_eq(r.cases[0].outcome.label(), "failed")
  assert_eq(r.cases[0].attempts, 2)
  assert_true(r.cases[0].flaky)
  assert_eq(r.diagnostics[0].code, "duplicate_attempt")
}

///|
test "cross-file duplicate merge uses declared order" {
  let a = parse_report("<testsuite><testcase name='x'><error/></testcase></testsuite>", source="a")
  let b = parse_report("<testsuite><testcase name='x'/></testsuite>", source="b")
  assert_true(try { ignore(merge_reports([a,b])); false } catch { _ => true })
  let r = merge_reports([a,b], duplicates=Attempts)
  assert_eq(r.cases[0].outcome.label(), "passed")
  assert_eq(r.cases[0].source, "b")
  assert_true(r.cases[0].flaky)
}

///|
test "Surefire retry outcome combinations fail closed" {
  let inputs = [
    ("<failure/><rerunFailure/>", "failed", 2, false),
    ("<error/><rerunError/>", "errored", 2, false),
    ("<flakyFailure/>", "passed", 2, true),
    ("<flakyError/><flakyFailure/>", "passed", 3, true),
    ("<failure/><flakyError/>", "failed", 2, true),
    ("<error/><flakyFailure/><rerunError/>", "errored", 3, true),
    ("<failure/><error/>", "errored", 1, false),
    ("<failure/><skipped/>", "failed", 1, false),
    ("<error/><skipped/>", "errored", 1, false),
    ("<skipped/>", "skipped", 1, false),
  ]
  for (body, outcome, attempts, flaky) in inputs {
    let r = parse_report("<testsuite><testcase name='x'>\{body}</testcase></testsuite>")
    assert_eq(r.cases[0].outcome.label(), outcome)
    assert_eq(r.cases[0].attempts, attempts)
    assert_eq(r.cases[0].flaky, flaky)
  }
  for body in ["<rerunFailure/>", "<flakyFailure/><rerunError/>", "<skipped/><flakyFailure/>", "<skipped/><failure/><rerunFailure/>"] {
    assert_true(rejects("<testsuite><testcase name='x'>\{body}</testcase></testsuite>"))
  }
}

///|
test "malformed inputs are errors not empty passing reports" {
  for xml in [
    "", " ", "<testsuite>", "<testsuite><testcase name='a'></testsuite>",
    "<root/>", "<testsuite/><testsuite/>", "<testsuite><testcase/></testsuite>",
    "<testsuite><testcase name=''/></testsuite>", "<testsuite><testcase name='&bad;'/></testsuite>",
    "<testsuite><testcase name='a' name='b'/></testsuite>",
    "<testsuites><testcase name='a'/></testsuites>",
    "<testsuite><x><testcase name='a'/></x></testsuite>",
    "<!DOCTYPE testsuite><testsuite/>",
    "<?xml version='1.0' encoding='ISO-8859-1'?><testsuite/>",
    "<testsuite xmlns='urn:x'/>",
  ] { assert_true(rejects(xml), msg=xml) }
}

///|
test "duration decimal bounds and invalid values" {
  assert_eq(parse_duration(""), None)
  assert_eq(parse_duration("0.0000009"), Some(0L))
  assert_eq(parse_duration("9000000.0000000"), Some(9000000000000L))
  assert_eq(parse_duration("001.2"), Some(1200000L))
  for time in ["-1", "1e3", "NaN", "inf", ".1", "1.", " 1", "1,234.5", "9000000.1", "999999999999999999999999"] {
    assert_true(try { ignore(parse_duration(time)); false } catch { _ => true }, msg=time)
  }
}

///|
test "unknown elements warn and output logs are not failure messages" {
  let r = parse_report("<testsuite><extra/><extra/><testcase name='x'><flakyFailure message='bad'><stackTrace>trace</stackTrace><system-out>SECRET_LOG</system-out></flakyFailure><system-out>ignored</system-out></testcase></testsuite>")
  assert_eq(r.diagnostics.length(), 1)
  assert_eq(r.cases[0].message, "badtrace")
}

///|
test "depth and message budgets" {
  let deep = "<testsuite>".repeat(129) + "</testsuite>".repeat(129)
  assert_true(rejects(deep))
  let r = parse_report("<testsuite><testcase name='x'><failure>" + "x".repeat(3000) + "</failure></testcase></testsuite>")
  assert_eq(r.cases[0].message.length(), 2048)
}
