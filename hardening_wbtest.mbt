///|
test "interned identity ranks exactly match full JSON lexical ordering" {
  let pool = new_scope_pool()
  let parts = ["", "a", "a\"", "a\\", "[x]", "\n", "😀", "中文", "\u{009b}"]
  for part in parts {
    ignore(pool.intern(-1, part))
    let parent = pool.intern(0, part)
    for child in parts {
      ignore(pool.intern(parent, child))
    }
  }
  let ranks = pool.ranks()
  let full : Array[(Int32, String)] = []
  for i = 0; i < pool.scopes.length(); i = i + 1 {
    let scope = pool.scopes[i]
    let id : TestId = if scope.kind == 0 {
      Class(scope.component, "test")
    } else {
      SuitePath(scope.path, "test")
    }
    full.push((i, id.key()))
    for name in parts {
      let id : TestId = if scope.kind == 0 {
        Class(scope.component, name)
      } else {
        SuitePath(scope.path, name)
      }
      assert_eq(
        scope.id_units(Json(name).stringify(), 0),
        id.key().length().to_int64(),
      )
      assert_eq(
        scope.id_units(Json(name).stringify(), 1),
        safe_cell(id.key()).length().to_int64(),
      )
      assert_eq(
        scope.id_units(Json(name).stringify(), 2),
        terminal_text(id.key()).length().to_int64(),
      )
    }
  }
  full.sort_by((a, b) => a.1.lexical_compare(b.1))
  for i = 0; i < full.length(); i = i + 1 {
    assert_eq(ranks[full[i].0], i)
  }
}

///|
test "JSON size measurement agrees with serializer for escapes and Unicode" {
  let chars = StringBuilder()
  for i = 0; i < 256; i = i + 1 {
    chars.write_char(i.unsafe_to_char())
  }
  chars.write_string("😀中文/\\\"")
  let text = chars.to_string()
  assert_eq(string_json_units(text), Json(text).stringify().length().to_int64())
  let value : Json = {
    "nested": [Json(text), null, true, false, 1, -42, 9000000000000],
    "empty": [],
  }
  assert_eq(json_units(value), value.stringify().length().to_int64())
  assert_eq(safe_units(text), safe_cell(text).length().to_int64())
  assert_eq(terminal_units(text), terminal_text(text).length().to_int64())
}

///|
test "render budgets accept exact size and reject one unit less" {
  let source = "source\n\"\\😀"
  let before = parse_report(
    "<testsuite name='&quot;|😀'><testcase name='x'/><testcase classname='C' name='removed'/></testsuite>",
    source~,
  )
  let after = parse_report(
    "<testsuite name='&quot;|😀'><extra/><testcase name='x'><failure message='bad'>trace</failure></testcase><testcase classname='C' name='added'/></testsuite>",
    source~,
  )
  let report = after.to_json().stringify()
  assert_eq(
    after.to_json(max_units=report.length().to_int64()).stringify(),
    report,
  )
  assert_true(
    try {
      ignore(after.to_json(max_units=report.length().to_int64() - 1L))
      false
    } catch {
      Rejected("output_limit", _) => true
      _ => false
    },
  )
  let result = compare([before], after)
  let json = result.to_json_string()
  assert_eq(result.to_json_string(max_units=json.length().to_int64()), json)
  assert_true(
    try {
      ignore(result.to_json_string(max_units=json.length().to_int64() - 1L))
      false
    } catch {
      Rejected("output_limit", _) => true
      _ => false
    },
  )
  let md = result.to_markdown()
  assert_eq(result.to_markdown(max_units=md.length().to_int64()), md)
  assert_true(
    try {
      ignore(result.to_markdown(max_units=md.length().to_int64() - 1L))
      false
    } catch {
      Rejected("output_limit", _) => true
      _ => false
    },
  )
  let text = result.to_text()
  assert_eq(result.to_text(max_units=text.length().to_int64()), text)
  assert_true(
    try {
      ignore(result.to_text(max_units=text.length().to_int64() - 1L))
      false
    } catch {
      Rejected("output_limit", _) => true
      _ => false
    },
  )
}

///|
test "long shared paths compare normally and excessive output fails explicitly" {
  let xml = "<testsuite name='\{"x".repeat(200000)}'>" +
    "<testcase name='x'/><testcase name='y'/></testsuite>"
  let report = parse_report(xml)
  let result = compare([report], report)
  assert_eq(result.entries.length(), 2)
  assert_eq(result.exit_code(), 0)
  assert_true(result.to_markdown(limit=0).length() < 1024)
  assert_true(
    try {
      ignore(result.to_json(max_units=10000L))
      false
    } catch {
      Rejected("output_limit", _) => true
      _ => false
    },
  )
}

///|
test "merge retries use document order including nested suites" {
  let xml = "<testsuite><testsuite><testcase classname='C' name='x'><failure/></testcase></testsuite><testcase classname='C' name='x'/></testsuite>"
  let raw = parse_document(xml)
  let normalized = parse_report(xml, duplicates=Attempts)
  let merged = merge_reports([raw], duplicates=Attempts)
  assert_true(merged == normalized)
  assert_true(merged.cases[0].outcome == Passed)
  assert_eq(merged.cases[0].attempts, 2)
  assert_true(merge_reports([merged], duplicates=Attempts) == merged)
}

///|
test "public equality ignores private index cache and config copies arrays" {
  let report = parse_report("<testsuite><testcase name='x'/></testsuite>")
  let recached = { ..report.cases[0], scope: 999, source_units: 123L, }
  assert_true(recached == report.cases[0])
  let gates = ["removed"]
  let config = diff_config(fail_on=gates)
  gates.push("flaky")
  assert_eq(config.fail_on.length(), 1)
  let copied = report.cases.iter().to_array()
  copied.clear()
  assert_eq(report.cases.length(), 1)
}

///|
test "messages separate attribute and body and expose truncation" {
  let report = parse_report(
    "<testsuite><testcase name='x'><failure message='boom'>trace<![CDATA[tail]]></failure></testcase><testcase name='y'><failure>\{"x".repeat(2049)}</failure></testcase></testsuite>",
  )
  assert_eq(report.cases[0].message, "boom\ntracetail")
  assert_eq(report.cases[1].message.length(), 2048)
  assert_true(
    report.diagnostics.any(d => {
      d.code == "message_truncated" && d.message.contains("document index 1")
    }),
  )
}

///|
test "truncated XML cannot silently lose an unfinished testcase" {
  for
    xml in [
      "<testsuite><testcase name='x'", "<testsuite><testcase name='x'>", "<testsuite><testcase name='x'><failure>",
      "<testsuite><testcase name='x'/>", "<testsuite><testcase name='x'></wrong></testsuite>",
    ] {
    assert_true(rejects(xml), msg=xml)
  }
}

///|
test "CLI error fields cannot inject terminal controls or fake lines" {
  let result = run_cli(["compare", "--unknown\u{001b}[31m\nPASS", "x"], _ => "")
  assert_eq(result.status, 2)
  assert_false(result.stderr.contains("\u{001b}"))
  assert_true(result.stderr.contains("\\u001b"))
  assert_eq(result.stderr.split("\n").count(), 2)
}

///|
test "JSON rejects unpaired surrogates and extreme nesting" {
  for
    input in [
      "{\"op\":\"\\ud800\"}",
      "{\"op\":\"\\udc00\"}",
      "[".repeat(2000) + "0" + "]".repeat(2000),
    ] {
    assert_true(evaluate_request(input) is { "ok": false, "exit_code": 2, .. })
  }
}

///|
test "attribute budget runs before XML parsing and ignores quoted or opaque text" {
  let attrs = StringBuilder()
  for i = 0; i < 1024; i = i + 1 {
    attrs.write_string(" a\{i}='='")
  }
  assert_eq(
    parse_document("<testsuite\{attrs.to_string()}/>").cases.length(),
    0,
  )
  assert_true(
    try {
      ignore(parse_document("<testsuite\{attrs.to_string()} over='x'/>"))
      false
    } catch {
      Rejected("limit_exceeded", _) => true
      _ => false
    },
  )
  let fake = "<fake a='\{"=".repeat(2048)}'>"
  assert_eq(
    parse_document(
      "<?meta \{fake}?><testsuite><!--\{fake}--><![CDATA[\{fake}]]><testcase name='\{"=".repeat(2048)}'/></testsuite>",
    ).cases.length(),
    1,
  )
}

///|
test "public retry and history limits include exact boundaries" {
  let template = parse_report("<testsuite><testcase name='x'/></testsuite>")
  let almost = {
    ..template,
    cases: [{ ..template.cases[0], attempts: 999999, }],
  }
  assert_eq(
    merge_reports([almost, template], duplicates=Attempts).cases[0].attempts,
    1000000,
  )
  assert_true(
    try {
      ignore(merge_reports([almost, template, template], duplicates=Attempts))
      false
    } catch {
      Rejected("limit_exceeded", _) => true
      _ => false
    },
  )
  assert_eq(compare(Array::make(50, template), template).history_count, 50)
  assert_true(
    try {
      ignore(compare(Array::make(51, template), template))
      false
    } catch {
      _ => true
    },
  )
}
