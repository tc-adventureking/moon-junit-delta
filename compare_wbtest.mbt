///|
fn state_report(
  state : String,
  time~ : String = "1",
) -> Report raise InputError {
  if state == "N" {
    return parse_report("<testsuite/>")
  }
  let body = match state {
    "F" => "<failure/>"
    "E" => "<error/>"
    "S" => "<skipped/>"
    "K" => "<flakyFailure/>"
    _ => ""
  }
  parse_report(
    "<testsuite name='s'><testcase classname='c' name='test' time='\{time}'>\{body}</testcase></testsuite>",
  )
}

///|
test "all 35 outcome combinations including annotated retry pass" {
  let states = ["N", "P", "F", "E", "S", "K"]
  let expected = [
    ["absent", "added", "added_failing", "added_failing", "added", "added"],
    [
      "removed", "unchanged", "new_failure", "new_failure", "newly_skipped", "unchanged",
    ],
    [
      "removed", "fixed", "still_failing", "still_failing", "newly_skipped", "fixed",
    ],
    [
      "removed", "fixed", "still_failing", "still_failing", "newly_skipped", "fixed",
    ],
    [
      "removed", "unskipped", "new_failure", "new_failure", "unchanged", "unskipped",
    ],
    [
      "removed", "unchanged", "new_failure", "new_failure", "newly_skipped", "unchanged",
    ],
  ]
  let mut checked = 0
  for i = 0; i < states.length(); i = i + 1 {
    for j = 0; j < states.length(); j = j + 1 {
      if i == 0 && j == 0 {
        continue
      }
      let d = compare([state_report(states[i])], state_report(states[j]))
      assert_eq(d.entries.length(), 1)
      assert_eq(
        d.entries[0].category,
        expected[i][j],
        msg="\{states[i]} -> \{states[j]}",
      )
      assert_eq(
        d.entries[0].after.map(c => c.flaky).unwrap_or(false),
        states[j] == "K",
      )
      checked = checked + 1
    }
  }
  assert_eq(checked, 35)
}

///|
test "historical flakiness cannot downgrade present failure" {
  let d = compare([state_report("F"), state_report("P")], state_report("F"))
  assert_eq(d.entries[0].category, "new_failure")
  assert_true(d.entries[0].known_flaky)
  assert_eq(d.exit_code(), 1)
}

///|
test "historical annotations remain visible when current passing result is unchanged" {
  for older in ["F", "E", "K"] {
    let d = compare([state_report(older), state_report("P")], state_report("P"))
    assert_eq(d.entries[0].category, "unchanged")
    assert_true(d.entries[0].known_flaky)
    assert_false(d.entries[0].after.unwrap().flaky)
    assert_eq(d.exit_code(), 0)
    assert_true(d.to_json_string().contains("\"known_flaky\":true"))
    assert_true(d.to_markdown().contains("historically inconsistent"))
    assert_true(d.to_text().contains("historically inconsistent"))
    assert_true(d.to_markdown(limit=0).contains("Shown 0 details"))
    assert_false(d.to_markdown(limit=0).contains("historically inconsistent"))
  }
  let stable = compare([state_report("P")], state_report("P"))
  assert_true(stable.to_markdown().contains("Shown 0 details"))
  assert_false(stable.to_text().contains("unchanged"))
}

///|
test "lower median duration strict percentage inclusive floor and missing times" {
  let history = [
    state_report("P", time="1"),
    state_report("P", time="2"),
    state_report("P", time="3"),
    state_report("P", time="100"),
  ]
  let d = compare(history, state_report("P", time="3.1"))
  assert_eq(d.entries[0].baseline_time_us, Some(2000000L))
  assert_true(d.entries[0].slowdown)
  assert_false(
    compare(history, state_report("P", time="3")).entries[0].slowdown,
  )
  let config = diff_config(slowdown_pct=0, slowdown_floor_us=200000L)
  assert_true(
    compare([state_report("P")], state_report("P", time="1.2"), config~).entries[0].slowdown,
  )
  assert_false(
    compare([state_report("P")], state_report("P", time="1.199999"), config~).entries[0].slowdown,
  )
  assert_false(
    compare([state_report("P", time="")], state_report("P", time="10")).entries[0].slowdown,
  )
  assert_false(
    compare([state_report("F")], state_report("P", time="100")).entries[0].slowdown,
  )
}

///|
test "duration arithmetic stays within Int64 at maximum valid values" {
  let config = diff_config(slowdown_pct=1000000)
  assert_false(
    compare(
      [state_report("P", time="9000000")],
      state_report("P", time="9000000"),
      config~,
    ).entries[0].slowdown,
  )
  assert_true(
    compare(
      [state_report("P", time="0")],
      state_report("P", time="9000000"),
      config~,
    ).entries[0].slowdown,
  )
}

///|
test "default removal empty report and explicit flaky gates" {
  let d = compare([state_report("F")], state_report("N"))
  assert_eq(d.violations.join(","), "empty_report,removed")
  assert_eq(compare([state_report("F")], state_report("K")).exit_code(), 0)
  assert_eq(
    compare(
      [state_report("F")],
      state_report("K"),
      config=diff_config(fail_on=["flaky"]),
    ).exit_code(),
    1,
  )
  assert_eq(
    compare(
      [state_report("P")],
      state_report("F"),
      config=diff_config(fail_on=[]),
    ).exit_code(),
    0,
  )
}

///|
test "rendering is deterministic and Markdown fields are inert" {
  let c = parse_report(
    "<testsuite><testcase classname='&lt;x&gt;' name='[link](x)|`*'><failure message='&lt;img&gt;|`[bad]' /></testcase></testsuite>",
  )
  let d = compare([state_report("N")], c)
  assert_eq(
    d.to_json_string(),
    compare([state_report("N")], c).to_json_string(),
  )
  let md = d.to_markdown()
  assert_false(md.contains("<img>"))
  assert_false(md.contains("[link]"))
  assert_true(md.contains("&lt;img&gt;&#124;&#96;&#91;bad&#93;"))
}

///|
test "JSON durations are numeric microseconds or null" {
  let d = compare([state_report("P")], state_report("P", time=""))
  let text = d.to_json_string()
  assert_true(text.contains("\"time_us\":1000000"))
  assert_true(text.contains("\"time_us\":null"))
  assert_true(text.contains("\"baseline_time_us\":1000000"))
}

///|
test "rendering preserves Unicode prefixes and escapes terminal and Markdown syntax" {
  let prefix = "a".repeat(239)
  let c = parse_report(
    "<testsuite><testcase classname='Outer$Mid$Inner' name='x&#10;JUnit Delta: PASS&#13;&#9;&#127;&#155;~~x~~'><failure message='\{prefix}😀'/></testcase></testsuite>",
  )
  let d = compare([state_report("N")], c)
  let md = d.to_markdown()
  assert_true(md.contains(prefix + "…"))
  assert_false(md.contains("😀"))
  assert_true(md.contains("Outer&#36;Mid&#36;Inner"))
  assert_true(md.contains("&#126;&#126;x&#126;&#126;"))
  assert_false(md.contains("\u{9b}"))
  let text = d.to_text()
  assert_true(text.contains("\\nJUnit Delta: PASS\\r\\t\\u007f\\u009b"))
  assert_false(text.contains("\nJUnit Delta: PASS"))
}

///|
test "input order does not change sorted JSON entries" {
  let a = "<testcase name='a'/><testcase name='b'><failure/></testcase>"
  let b = "<testcase name='b'><failure/></testcase><testcase name='a'/>"
  let base = state_report("N")
  assert_eq(
    compare([base], parse_report("<testsuite>\{a}</testsuite>")).to_json_string(),
    compare([base], parse_report("<testsuite>\{b}</testsuite>")).to_json_string(),
  )
}

///|
test "CLI returns precise status and rejects ambiguous options" {
  let read = fn(path : String) -> String raise {
    if path == "missing" {
      raise InvalidInput("file not found")
    }
    match path {
      "old" => "<testsuite><testcase name='x'/></testsuite>"
      "new" => "<testsuite><testcase name='x'><failure/></testcase></testsuite>"
      _ => "<testsuite/>"
    }
  }
  let args = ["compare", "--baseline", "old", "--candidate", "new"]
  assert_eq(run_cli(args, read).status, 1)
  assert_eq(run_cli(args + ["--fail-on", "none"], read).status, 0)
  for
    extra in [
      ["--format", "xml"],
      ["--oops", "x"],
      ["--slowdown-pct", "-1"],
      ["--fail-on", "typo"],
      ["--limit"],
      ["--format", "json", "--format", "md"],
    ] {
    assert_eq(run_cli(args + extra, read).status, 2)
  }
  assert_eq(run_cli(["--help"], read).status, 0)
  assert_eq(
    run_cli(["--version"], read).stdout,
    "junit-delta \{release_version}\n",
  )
  assert_eq(
    run_cli(["compare", "--baseline", "-", "--candidate", "-"], read).status,
    2,
  )
  assert_eq(
    run_cli(["compare", "--baseline", "missing", "--candidate", "new"], read).status,
    2,
  )
}

///|
test "JSON protocol rejects duplicate keys invalid options and missing runs" {
  for
    text in [
      "{", "{}", "{\"candidate\":{},\"candidate\":{}}", "{\"baselines\":[],\"candidate\":{}}",
    ] {
    let result = evaluate_request(text)
    assert_eq(integer_field(result, "exit_code", 0L, 2L), 2L)
  }
}
