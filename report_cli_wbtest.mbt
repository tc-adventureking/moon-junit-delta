///|
test "mixed root and nested cases retain identities, results, logs and statistics" {
  let xml = "<testsuites><testcase name='top' time='0.25'><failure/><system-out>trace</system-out></testcase><testsuite name='a'><testsuite name='inner'><testcase name='leaf' time='0.5'><skipped/></testcase></testsuite></testsuite></testsuites>"
  let verify = run_cli(["verify", "node.xml"], _ => xml)
  assert_eq(verify.status, 1)
  assert_true(verify.stderr.contains("top"))
  let merged = run_cli(["merge", "node.xml", "-"], _ => xml)
  assert_eq(merged.status, 0)
  let result = JUnitDocument::from_xml(merged.stdout)
  assert_eq(result.root.attribute("tests"), Some("2"))
  assert_eq(result.root.attribute("failures"), Some("1"))
  assert_eq(result.root.attribute("skipped"), Some("1"))
  assert_eq(result.root.attribute("time"), Some("0.75"))
  assert_eq(result.root.elements(name=Some("testcase")).length(), 1)
  assert_true(merged.stdout.contains("<system-out>trace</system-out>"))
  let before = parse_report(xml)
  let after = parse_report(merged.stdout)
  let delta = compare([before], after)
  assert_eq(delta.entries.length(), 2)
  for entry in delta.entries {
    assert_true(
      entry.category == "still_failing" || entry.category == "unchanged",
    )
  }
}

///|
test "verify requires cases across the supplied reports and ignores extension children" {
  let empty = "<testsuites><vendor><testcase name='ignored'><failure/></testcase></vendor></testsuites>"
  let pass = "<testsuite><testcase name='ok'/></testsuite>"
  assert_eq(run_cli(["verify", "empty"], _ => empty).status, 1)
  assert_eq(
    run_cli(["verify", "empty", "pass"], path => {
      if path == "empty" {
        empty
      } else {
        pass
      }
    }).status,
    0,
  )
  let skipped = "<testsuites><testcase name='both'><failure/><skipped/></testcase></testsuites>"
  assert_eq(run_cli(["verify", "-"], _ => skipped).status, 0)
}

///|
test "each glob needs an input, and merge errors leave the output untouched" {
  let writes : Array[String] = []
  let result = run_cli(
    ["merge", "--glob", "good", "bad", "out"],
    _ => "<testsuite><testcase name='ok'/></testsuite>",
    glob=Some(pattern => if pattern == "good" { ["shard"] } else { [] }),
    write=Some((_, xml) => writes.push(xml)),
  )
  assert_eq(result.status, 1)
  assert_true(result.stderr.contains("bad"))
  assert_true(writes.is_empty())
}

///|
test "glob skips output aliases and reads stdin once" {
  let reads : Array[String] = []
  let writes : Array[String] = []
  let xml = "<testsuites><testcase name='ok'/></testsuites>"
  let result = run_cli(
    ["merge", "--glob", "pattern", "-", "out"],
    path => {
      reads.push(path)
      xml
    },
    glob=Some(pattern => {
      if pattern == "pattern" {
        ["alias", "shard"]
      } else {
        []
      }
    }),
    same_file=(input, output) => input == "alias" && output == "out",
    write=Some((_, text) => writes.push(text)),
  )
  assert_eq(result.status, 0)
  assert_eq(reads, ["shard", "-"])
  assert_eq(
    JUnitDocument::from_xml(writes[0]).root.attribute("tests"),
    Some("2"),
  )
  assert_eq(run_cli(["verify", "--glob", "-", "-"], _ => xml).status, 1)
}
