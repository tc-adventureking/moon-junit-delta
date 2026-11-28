///|
fn document_expect_error(run : () -> Unit raise) -> Unit raise {
  let failed = try {
    run()
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "document create edit serialize and compare projection" {
  let case = JUnitElement::testcase(
      "login",
      classname=Some("api"),
      time_us=Some(100001L),
    )
    .add_property("build", "12")
    .with_output("system-out", "hello <&>\n")
  let suite = JUnitElement::suite("service").append(Element(case))
  let doc = JUnitDocument::new(root=suite).with_statistics()
  assert_eq(doc.root.attribute("tests"), Some("1"))
  assert_eq(doc.root.attribute("time"), Some("0.100001"))
  let edited = doc
    .map_cases(c => {
      Some(
        c.with_results([
          JUnitElement::result("failure", message="no", body="stack"),
        ]),
      )
    })
    .with_statistics()
  assert_eq(doc.root.attribute("failures"), Some("0"))
  assert_eq(edited.root.attribute("failures"), Some("1"))
  let reread = JUnitDocument::from_xml(edited.to_xml())
  assert_eq(reread.to_xml(), edited.to_xml())
  assert_true(reread.to_report().cases[0].outcome == Failed)
  assert_true(reread.to_xml().contains("hello &lt;&amp;&gt;\n"))
}

///|
test "document preserves extension nodes mixed text attributes and prolog" {
  let input = "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\n<!--before--><?build ci?><testsuites xmlns:e='urn:extra' name='run' e:owner='a&#10;b&#9;c&#13;d'><testsuite name='s'><properties><property name='text'>v&amp;x</property></properties><testcase name='x' custom='yes'><failure message='m'><e:detail>before<b/>after</e:detail></failure><system-out><![CDATA[a<&b]]></system-out><!--inside--><?note ok?></testcase></testsuite></testsuites><!--after-->"
  let doc = JUnitDocument::from_xml(input)
  assert_eq(doc.root.attribute("e:owner"), Some("a\nb\tc\rd"))
  let output = doc.to_xml()
  assert_true(output.contains("<![CDATA[a<&b]]>"))
  assert_true(output.contains("<!--inside-->"))
  assert_true(output.contains("<?note ok?>"))
  assert_true(output.contains("before<b/>after"))
  assert_true(output.contains("a&#10;b&#9;c&#13;d"))
  assert_eq(JUnitDocument::from_xml(output).to_xml(), output)
  document_expect_error(fn() raise { ignore(doc.to_report()) })
}

///|
test "document has no lossy 2048 character message cap" {
  let message = String::make(4096, '中') + "😀"
  let c = JUnitElement::testcase("x").with_results([
    JUnitElement::result("failure", message~),
  ])
  let d = JUnitDocument::new(root=JUnitElement::suite("s").append(Element(c)))
  let p = JUnitDocument::from_xml(d.to_xml()).root.elements()[0]
  assert_eq(p.elements()[0].attribute("message"), Some(message))
  assert_eq(d.to_report().cases[0].message.length(), 2048)
}

///|
test "document snapshots caller owned arrays" {
  let attrs = [("name", "a")]
  let nodes = [Text("hello")]
  let child = JUnitElement::new("system-out", attributes=attrs, content=nodes)
  attrs[0] = ("name", "changed")
  nodes[0] = Text("changed")
  assert_eq(child.attribute("name"), Some("a"))
  let d = JUnitDocument::new(
    root=JUnitElement::suite("s").append(Element(child)),
  )
  assert_true(d.to_xml().contains(">hello</system-out>"))
}

///|
test "document remove structural cases and suites keeps opaque extensions" {
  let d = JUnitDocument::from_xml(
    "<testsuites><testsuite name='a'><testcase name='x'/><extra><testcase name='opaque'/></extra><testsuite name='nested'><testcase name='y'/></testsuite></testsuite><testcase name='root'/></testsuites>",
  )
  let mut count = 0
  let empty = d
    .map_cases(_ => {
      count = count + 1
      None
    })
    .with_statistics()
  assert_eq(count, 3)
  assert_eq(empty.root.attribute("tests"), Some("0"))
  assert_true(empty.to_xml().contains("name=\"opaque\""))
  let removed = d.map_suites(_ => None).with_statistics()
  assert_eq(removed.root.attribute("tests"), Some("1"))
  document_expect_error(fn() raise {
    ignore(d.map_cases(_ => Some(JUnitElement::suite("bad"))))
  })
  document_expect_error(fn() raise {
    ignore(d.map_suites(_ => Some(JUnitElement::new("bad"))))
  })
}

///|
test "document statistics count cases and preserve suite wall time" {
  let d = JUnitDocument::from_xml(
    "<testsuite time='9' disabled='2'><testcase name='a' time='0.1'><failure/><failure/></testcase><testsuite><testcase name='b' time='0.2'><skipped/><error/></testcase><testcase name='c'><flakyFailure/></testcase></testsuite></testsuite>",
  )
  let normal = d.with_statistics()
  assert_eq(normal.root.attribute("tests"), Some("3"))
  assert_eq(normal.root.attribute("failures"), Some("1"))
  assert_eq(normal.root.attribute("errors"), Some("1"))
  assert_eq(normal.root.attribute("skipped"), Some("0"))
  assert_eq(normal.root.attribute("time"), Some("9.000000"))
  assert_eq(normal.root.attribute("disabled"), Some("2"))
  let recomputed = d.with_statistics(overwrite_time=true)
  assert_eq(recomputed.root.attribute("time"), Some("0.300000"))
  assert_eq(recomputed.with_statistics().to_xml(), recomputed.to_xml())
  assert_eq(
    JUnitDocument::from_xml("<testsuite><testcase name='x'/></testsuite>").with_statistics().root.attribute(
      "time",
    ),
    None,
  )
}

///|
test "document statistics checked decimal range and overflow" {
  assert_eq(
    document_time_us("9223372036854.775807"),
    Some(9223372036854775807L),
  )
  assert_eq(document_time_us("0.0000019"), Some(1L))
  for
    bad in [
      "-1", ".1", "1.", "1e3", "NaN", "9223372036854.775808", "9223372036855",
    ] {
    document_expect_error(fn() raise { ignore(document_time_us(bad)) })
  }
  let maxcase = JUnitElement::testcase(
    "max",
    time_us=Some(9223372036854775807L),
  )
  let suite = JUnitElement::suite("s").append(Element(maxcase))
  let d = JUnitDocument::new(root=suite).with_statistics()
  assert_eq(d.root.attribute("time"), Some("9223372036854.775807"))
  assert_eq(d.with_statistics().to_xml(), d.to_xml())
  document_expect_error(fn() raise {
    ignore(
      JUnitDocument::new(
        root=suite.append(
          Element(JUnitElement::testcase("one", time_us=Some(1L))),
        ),
      ).with_statistics(),
    )
  })
}

///|
test "document merge preserves independent suites and source metadata" {
  let a = JUnitDocument::from_xml(
    "<testsuites name='run' tests='99' xmlns:e='urn:e'><testsuite name='s'><testcase name='x' e:id='1'/></testsuite><e:meta>ok</e:meta></testsuites>",
  )
  let b = JUnitDocument::from_xml(
    "<testsuites name='run' tests='10' xmlns:e='urn:e'><testsuite name='s'><testcase name='x' e:id='2'/></testsuite></testsuites>",
  )
  let merged = merge_documents([a, b])
  assert_eq(merged.root.attribute("tests"), None)
  assert_eq(merged.root.attribute("name"), Some("run"))
  assert_eq(merged.root.elements(name=Some("testsuite")).length(), 2)
  assert_true(merged.to_xml().contains("<e:meta>ok</e:meta>"))
  assert_eq(merged.with_statistics().root.attribute("tests"), Some("2"))
  assert_eq(JUnitDocument::from_xml(merged.to_xml()).to_xml(), merged.to_xml())
  assert_eq(merge_documents([]).to_xml(), "<testsuites/>")
  assert_eq(merge_documents([a]).to_xml(), a.to_xml())
}

///|
test "document merge rejects conflicting metadata and namespace bindings" {
  let a = JUnitDocument::from_xml(
    "<testsuites name='a' xmlns:e='urn:a'><testsuite e:id='1'/></testsuites>",
  )
  for
    input in [
      "<testsuites name='b' xmlns:e='urn:a'/>", "<testsuites name='a' xmlns:e='urn:b'/>",
      "<testsuites/>", "<!--different--><testsuites name='a' xmlns:e='urn:a'/>",
    ] {
    document_expect_error(fn() raise {
      ignore(merge_documents([a, JUnitDocument::from_xml(input)]))
    })
  }
  let b = JUnitDocument::from_xml("<testsuite xmlns:e='urn:b' e:id='2'/>")
  let merged = merge_documents([a, b])
  assert_true(merged.to_xml().contains("xmlns:e=\"urn:b\""))
}

///|
test "document XML validation and output budget before sink" {
  for
    input in [
      "<!DOCTYPE testsuite><testsuite/>", "<testsuite xmlns='urn:no'/>", "<testsuite x:attr='1'/>",
      "<root/>", "<testsuite><x></testsuite>", "<testsuite a='1' a='2'/>", "<?xml version='1.0' encoding='ISO-8859-1'?><testsuite/>",
    ] {
    document_expect_error(fn() raise { ignore(JUnitDocument::from_xml(input)) })
  }
  let d = JUnitDocument::new(
    root=JUnitElement::suite("s<&\n\r\t\"'😀").append(Text("a\rb<&\"'😀")),
  )
  let output = d.to_xml()
  assert_eq(d.to_xml(max_units=output.length().to_int64()), output)
  document_expect_error(fn() raise {
    ignore(d.to_xml(max_units=output.length().to_int64() - 1L))
  })
  let mut calls = 0
  document_expect_error(fn() raise {
    d.write_to(_ => calls = calls + 1, max_units=1L)
  })
  assert_eq(calls, 0)
  let mut received = ""
  d.write_to(text => received = text)
  assert_eq(received, output)
  for
    node in [
      Text("\u0001"),
      Comment("bad--comment"),
      CData("]]>"),
      Instruction("xml", "bad"),
      Instruction("ok", "a?>injection"),
    ] {
    document_expect_error(fn() raise {
      ignore(
        JUnitDocument::new(root=JUnitElement::suite("s").append(node)).to_xml(),
      )
    })
  }
}

///|
test "document depth and attribute bounds are applied to edits" {
  let mut child = JUnitElement::new("extra")
  for _i = 0; _i < 126; _i = _i + 1 {
    child = JUnitElement::new("extra", content=[Element(child)])
  }
  let d = JUnitDocument::new(
    root=JUnitElement::suite("s").append(Element(child)),
  )
  ignore(d.to_xml())
  let deep = d.with_root(JUnitElement::suite("s").append(Element(d.root)))
  document_expect_error(fn() raise { ignore(deep.to_xml()) })
  let attrs = Array::makei(1025, i => ("a\{i}", "x"))
  document_expect_error(fn() raise {
    ignore(
      JUnitDocument::new(root=JUnitElement::new("testsuite", attributes=attrs)).to_xml(),
    )
  })
}

///|
test "extension namespaces round trip and invalid document roots are rejected" {
  let source = "<testsuite><testcase name='c'><ext xmlns='urn:v'><property/><testcase name='opaque'/></ext></testcase></testsuite>"
  let d = JUnitDocument::from_xml(source)
  assert_eq(JUnitDocument::from_xml(d.to_xml()).to_xml(), d.to_xml())
  assert_eq(d.with_statistics().root.attribute("tests"), Some("1"))
  let core = JUnitDocument::new(root=JUnitElement::suite("s"))
  for
    root in [
      JUnitElement::new("testsuites", attributes=[("xmlns", "urn:a")]),
      JUnitElement::new("other"),
      JUnitElement::new("j:testsuite", attributes=[("xmlns:j", "urn:a")]),
    ] {
    document_expect_error(fn() raise {
      ignore(merge_documents([JUnitDocument::new(root~), core]))
    })
  }
  for
    bad in [
      "<testsuites/><testsuite name='x'>", "<testsuites/>junk", "<testsuites><![CDATA[x]]>",
      "<testsuite><testcase xmlns='urn:v'/></testsuite>",
    ] {
    document_expect_error(fn() raise { ignore(JUnitDocument::from_xml(bad)) })
  }
}

///|
test "declared XML respects the exact output budget and propagates sink errors" {
  let d = JUnitDocument::from_xml(
    "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\n<!--before--><?build ci?><testsuite name='中文😀'/>\n",
  )
  let output = d.to_xml()
  assert_eq(d.to_xml(max_units=output.length().to_int64()), output)
  document_expect_error(fn() raise {
    ignore(d.to_xml(max_units=output.length().to_int64() - 1L))
  })
  let error = try {
    d.write_to(fn(_) raise { raise InvalidInput("sink failed") })
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_true(error.contains("sink failed"))
  document_expect_error(fn() raise {
    ignore(
      JUnitDocument::from_xml(
        "<testsuite time='1'><testcase name='x' time='bad'/></testsuite>",
      ).with_statistics(),
    )
  })
}
