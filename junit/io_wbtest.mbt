///|
test "I/O byte sink, remembered filename, and fresh view" {
  let calls : Array[String] = []
  let doc = JUnitXml::from_file("report.xml", path => {
    calls.push("read:" + path)
    utf8_bytes("<testsuite><testcase/></testsuite>")
  })
  assert_eq(doc.filepath(), Some("report.xml"))
  doc.write((path, bytes) => {
    calls.push("write:" + path)
    assert_eq(
      @utf8.decode(bytes[:]),
      "<?xml version='1.0' encoding='UTF-8'?>\n<testsuites><testsuite><testcase/></testsuite></testsuites>",
    )
  })
  assert_eq(calls, ["read:report.xml", "write:report.xml"])
  assert_eq(JUnitXml::from_element(doc.element()).filepath(), None)
  let missing = try {
    JUnitXml::new().write((_, _) => abort("unreachable sink"))
    false
  } catch {
    MissingFile => true
    _ => false
  }
  assert_true(missing)
}

///|
test "I/O injected source parser completely replaces reading and parsing" {
  let calls = []
  let doc = JUnitXml::from_file_with("custom.csv", path => {
    calls.push(path)
    let suite = TestSuite::new(name=Some("converted"))
    suite.add_case(TestCase::new(name=Some("row")))
    suite.element()
  })
  assert_eq(calls, ["custom.csv"])
  assert_eq(doc.filepath(), Some("custom.csv"))
  assert_eq(doc.suites().next().unwrap().name(), Some("converted"))
  assert_eq(doc.suites().next().unwrap().len(), 1)
  let streamed = JUnitXml::from_reader(
    () => utf8_bytes("not XML"),
    parse=Some(_ => Element::new("testsuites")),
  )
  assert_eq(streamed.filepath(), None)
  assert_eq(streamed.len(), 0)
}

///|
suberror ProbeIoError {
  ProbeIoError
}

///|
test "I/O host exceptions are propagated" {
  let read_error = try {
    ignore(JUnitXml::from_file("x", _ => raise ProbeIoError))
    false
  } catch {
    ProbeIoError => true
    _ => false
  }
  let parse_error = try {
    ignore(JUnitXml::from_file_with("x", _ => raise ProbeIoError))
    false
  } catch {
    ProbeIoError => true
    _ => false
  }
  let write_error = try {
    JUnitXml::new().write_to(_ => raise ProbeIoError)
    false
  } catch {
    ProbeIoError => true
    _ => false
  }
  assert_true(read_error && parse_error && write_error)
}

///|
test "custom attributes and declared field types round trip" {
  let case = TestCase::new(name=Some("a"))
  case
  .element()
  .write_attribute("retryable", true, value => if value { "yes" } else { "no" })
  case.element().set_int_attribute("attempts", @bigint.BigInt::from_int(3))
  let restored = TestCase::from_string(case.element().to_xml())
  assert_eq(
    restored.element().read_attribute("retryable", text => text == "yes"),
    Some(true),
  )
  assert_eq(
    restored.element().int_attribute("attempts").unwrap().to_string(),
    "3",
  )
}

///|
test "UTF-16 XML preserves Unicode with either byte order and optional BOM" {
  let xml = "<?xml version='1.0' encoding='UTF-16'?><testsuite name='中文'><testcase name='😃'/></testsuite>"
  for endianness in [@utf16.Little, @utf16.Big] {
    for bom in [true, false] {
      let doc = JUnitXml::from_bytes(@utf16.encode(xml[:], endianness~, bom~))
      let suite = doc.suites().next().unwrap()
      assert_eq(suite.name(), Some("中文"))
      assert_eq(suite.cases().next().unwrap().name(), Some("😃"))
    }
  }
}
