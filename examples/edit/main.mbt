///|
fn main raise {
  let case = @junit.JUnitElement::testcase("login", classname=Some("api"))
  let suite = @junit.JUnitElement::suite("service")
    .add_property("build", "12")
    .append(@junit.JUnitNode::Element(case))
  let report = @junit.JUnitDocument::new(root=suite)
  let edited = report.map_cases(c => Some(c.with_attribute("file", "login.mbt")))
  edited.with_statistics().write_to(xml => println(xml))
}
