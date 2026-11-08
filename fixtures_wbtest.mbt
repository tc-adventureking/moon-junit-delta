// Generated from fixtures by the project fixture embedding script.

///|
test "fixture node.xml" {
  let r = parse_report(
    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<testsuites>\n\t<testsuite name=\"node fixture\" time=\"0.002486\" disabled=\"0\" errors=\"0\" tests=\"2\" failures=\"0\" skipped=\"1\" timestamp=\"2026-11-08T18:20:27.894Z\" hostname=\"fixture-host\">\n\t\t<testcase name=\"passes &amp; keeps unicode 中文\" time=\"0.000695\" classname=\"node fixture\" file=\"fixtures/generate/node-case.mjs\"/>\n\t\t<testcase name=\"planned test\" time=\"0.000372\" classname=\"node fixture\" file=\"fixtures/generate/node-case.mjs\">\n\t\t\t<skipped type=\"skipped\" message=\"true\"/>\n\t\t</testcase>\n\t</testsuite>\n\t<!-- tests 2 -->\n\t<!-- suites 1 -->\n\t<!-- pass 1 -->\n\t<!-- fail 0 -->\n\t<!-- cancelled 0 -->\n\t<!-- skipped 1 -->\n\t<!-- todo 0 -->\n\t<!-- duration_ms 147.4805 -->\n</testsuites>\n",
  )
  assert_eq(r.cases.length(), 2)
  assert_eq(r.cases[0].outcome.label(), "passed")
  assert_eq(r.cases[1].outcome.label(), "skipped")
}

///|
test "fixture surefire.xml" {
  let r = parse_report(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuite name=\"example.Math\" tests=\"3\" failures=\"1\" errors=\"0\" skipped=\"0\">\n  <testcase name=\"recovers\" classname=\"example.Math\" time=\"0.010\">\n    <flakyFailure message=\"first attempt\"><stackTrace>expected 4 but got 3</stackTrace></flakyFailure>\n  </testcase>\n  <testcase name=\"still_fails\" classname=\"example.Math\" time=\"0.020\">\n    <failure message=\"first failure\">assertion failed</failure>\n    <rerunFailure message=\"second failure\"><stackTrace>same assertion</stackTrace></rerunFailure>\n  </testcase>\n  <testcase name=\"works\" classname=\"example.Math\" time=\"0.005\"/>\n</testsuite>\n",
  )
  assert_eq(r.cases.length(), 3)
  assert_eq(r.cases[0].outcome.label(), "passed")
  assert_eq(r.cases[1].outcome.label(), "failed")
  assert_eq(r.cases[2].outcome.label(), "passed")
}

///|
test "fixture pytest.xml" {
  let r = parse_report(
    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<testsuites><testsuite name=\"pytest\" errors=\"1\" failures=\"1\" skipped=\"1\" tests=\"4\" time=\"0.053\">\n  <testcase classname=\"test_math\" name=\"test_sum[1-2]\" time=\"0.001\"/>\n  <testcase classname=\"test_math\" name=\"test_negative\" time=\"0.002\"><failure message=\"assert -1 == 1\">test_math.py:4: AssertionError</failure></testcase>\n  <testcase classname=\"test_math\" name=\"test_optional\" time=\"0\"><skipped type=\"pytest.skip\" message=\"optional\"/></testcase>\n  <testcase classname=\"test_math\" name=\"test_fixture\" time=\"0.050\"><error message=\"failed on setup\">fixture unavailable</error></testcase>\n</testsuite></testsuites>\n",
  )
  assert_eq(r.cases.length(), 4)
  assert_eq(r.cases[0].outcome.label(), "passed")
  assert_eq(r.cases[1].outcome.label(), "failed")
  assert_eq(r.cases[2].outcome.label(), "skipped")
  assert_eq(r.cases[3].outcome.label(), "errored")
}

///|
test "fixture gitlab.xml" {
  let r = parse_report(
    "<testsuites>\n  <testsuite name=\"Web request checks\">\n    <testcase classname=\"RequestTest\" name=\"invalid_input\" file=\"tests/request.test.js\" time=\"0.23\">\n      <failure message=\"validation changed\">expected 400</failure>\n      <system-out>[[ATTACHMENT|artifacts/request.png]]</system-out>\n    </testcase>\n  </testsuite>\n</testsuites>\n",
  )
  assert_eq(r.cases.length(), 1)
  assert_eq(r.cases[0].outcome.label(), "failed")
}
