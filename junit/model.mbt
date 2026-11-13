// Portions adapted from junitparser 5.0.3.
// Copyright 2025 Weiwei Wang.
// MoonBit adaptation and additions: 2026 tc-adventureking.
// SPDX-License-Identifier: Apache-2.0
// See third_party/junitparser-LICENSE and third_party/NOTICE.md.

///|
/// Select the base schema or junitparser.xunit2 behavior.
#derive(Eq)
pub(all) enum Flavor {
  Base
  XUnit2
}

///|
pub extend Flavor with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) enum ResultKind {
  Failure
  Error
  Skipped
  RerunFailure
  RerunError
  FlakyFailure
  FlakyError
}

///|
pub extend ResultKind with Eq::{equal, not_equal}

///|
pub fn ResultKind::tag(self : ResultKind) -> String {
  match self {
    Failure => "failure"
    Error => "error"
    Skipped => "skipped"
    RerunFailure => "rerunFailure"
    RerunError => "rerunError"
    FlakyFailure => "flakyFailure"
    FlakyError => "flakyError"
  }
}

///|
pub fn ResultKind::is_final(self : ResultKind) -> Bool {
  self is Failure || self is Error || self is Skipped
}

///|
fn result_kind(tag : String) -> ResultKind? {
  match tag {
    "failure" => Some(Failure)
    "error" => Some(Error)
    "skipped" => Some(Skipped)
    "rerunFailure" => Some(RerunFailure)
    "rerunError" => Some(RerunError)
    "flakyFailure" => Some(FlakyFailure)
    "flakyError" => Some(FlakyError)
    _ => None
  }
}

///|
struct TestResult {
  element_ : Element
  kind_ : ResultKind
}

///|
pub fn TestResult::new(
  kind : ResultKind,
  message~ : String? = None,
  type_~ : String? = None,
) -> TestResult raise JUnitError {
  let element_ = Element::new(kind.tag())
  if message is Some(message) && message != "" {
    element_.set_attribute("message", Some(message))
  }
  if type_ is Some(type_) && type_ != "" {
    element_.set_attribute("type", Some(type_))
  }
  { element_, kind_: kind, }
}

///|
pub fn TestResult::from_element(
  element : Element,
  kind : ResultKind,
) -> TestResult {
  { element_: element, kind_: kind, }
}

///|
pub fn TestResult::element(self : TestResult) -> Element {
  self.element_
}

///|
pub fn TestResult::kind(self : TestResult) -> ResultKind {
  self.kind_
}

///|
/// Result equality ignores body text and compares kind, type and message.
pub fn TestResult::equal(self : TestResult, other : TestResult) -> Bool {
  self.kind_ == other.kind_ &&
  self.element_.attribute("message") == other.element_.attribute("message") &&
  self.element_.attribute("type") == other.element_.attribute("type")
}

///|
pub fn TestResult::text(self : TestResult) -> String? {
  self.element_.text()
}

///|
pub fn TestResult::set_text(
  self : TestResult,
  text : String?,
) -> Unit raise JUnitError {
  self.element_.set_text(text)
}

///|
#derive(Eq)
pub(all) enum OutputKind {
  SystemOut
  SystemErr
  StackTrace
}

///|
pub extend OutputKind with Eq::{equal, not_equal}

///|
pub fn OutputKind::tag(self : OutputKind) -> String {
  match self {
    SystemOut => "system-out"
    SystemErr => "system-err"
    StackTrace => "stackTrace"
  }
}

///|
pub fn output_element(
  kind : OutputKind,
  text~ : String? = None,
) -> Element raise JUnitError {
  let element = Element::new(kind.tag())
  element.set_text(text)
  element
}

///|
struct Property {
  element_ : Element
}

///|
pub fn Property::new(
  name~ : String? = None,
  value~ : String? = None,
) -> Property raise JUnitError {
  let element_ = Element::new("property")
  element_.set_attribute("name", name)
  element_.set_attribute("value", value)
  { element_, }
}

///|
pub fn Property::from_element(element : Element) -> Property {
  { element_: element, }
}

///|
pub fn Property::element(self : Property) -> Element {
  self.element_
}

///|
pub fn Property::equal(self : Property, other : Property) -> Bool {
  self.element_.attribute("name") == other.element_.attribute("name") &&
  self.element_.attribute("value") == other.element_.attribute("value")
}

///|
fn unicode_compare(a : String, b : String) -> Int32 {
  let left = a.iter()
  let right = b.iter()
  while true {
    match (left.next(), right.next()) {
      (None, None) => return 0
      (None, _) => return -1
      (_, None) => return 1
      (Some(a), Some(b)) => {
        let difference = a.to_int() - b.to_int()
        if difference != 0 {
          return difference
        }
      }
    }
  } nobreak {
    0
  }
}

///|
/// Python's Property ordering is descending by name.
pub fn Property::less(
  self : Property,
  other : Property,
) -> Bool raise JUnitError {
  match (self.element_.attribute("name"), other.element_.attribute("name")) {
    (Some(a), Some(b)) => unicode_compare(a, b) > 0
    _ => raise InvalidValue("cannot order a property with a missing name")
  }
}

///|
struct Properties {
  element_ : Element
}

///|
pub fn Properties::new() -> Properties raise JUnitError {
  { element_: Element::new("properties"), }
}

///|
pub fn Properties::from_element(element : Element) -> Properties {
  { element_: element, }
}

///|
pub fn Properties::element(self : Properties) -> Element {
  self.element_
}

///|
pub fn Properties::iter(self : Properties) -> Iter[Property] {
  self.element_.iter_children(name=Some("property")).map(Property::from_element)
}

///|
pub fn Properties::add(
  self : Properties,
  property : Property,
) -> Unit raise JUnitError {
  self.element_.append(property.element_)
}

///|
pub fn Properties::remove(
  self : Properties,
  property : Property,
) -> Unit raise JUnitError {
  for child in self.iter() {
    if child.equal(property) {
      self.element_.remove_node(child.element_)
    }
  }
}

///|
fn sorted_properties(
  properties : Array[Property],
  reverse : Bool,
) -> Array[Property] raise JUnitError {
  // Carry original indices explicitly; duplicate names retain source order.
  let indexed : Array[(Property, Int32)] = []
  for i = 0; i < properties.length(); i = i + 1 {
    indexed.push((properties[i], i))
  }
  if properties.length() > 1 {
    for property in properties {
      if property.element_.attribute("name") is None {
        raise InvalidValue("cannot sort a property with a missing name")
      }
    }
  }
  indexed.sort_by(fn(a, b) {
    let order = unicode_compare(
      a.0.element_.attribute("name").unwrap_or(""),
      b.0.element_.attribute("name").unwrap_or(""),
    )
    if order == 0 {
      a.1 - b.1
    } else if reverse {
      -order
    } else {
      order
    }
  })
  indexed.map(item => item.0)
}

///|
pub fn Properties::equal(
  self : Properties,
  other : Properties,
) -> Bool raise JUnitError {
  let a = sorted_properties(self.iter().to_array(), true)
  let b = sorted_properties(other.iter().to_array(), true)
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if !a[i].equal(b[i]) {
      return false
    }
  }
  true
}

///|
fn Element::properties(self : Element) -> Iter[Property] {
  let mut started = false
  let mut iterator : Iter[Property]? = None
  Iter::new(fn() {
    if !started {
      started = true
      iterator = self
        .child("properties")
        .map(element => Properties::from_element(element).iter())
    }
    match iterator {
      Some(iterator) => iterator.next()
      None => None
    }
  })
}

///|
fn Element::add_property(
  self : Element,
  name : String,
  value : String,
) -> Unit raise JUnitError {
  let properties = match self.child("properties") {
    Some(element) => Properties::from_element(element)
    None => {
      let props = Properties::new()
      self.append(props.element_)
      props
    }
  }
  properties.add(Property::new(name=Some(name), value=Some(value)))
}

///|
fn Element::remove_property(
  self : Element,
  property : Property,
) -> Unit raise JUnitError {
  if self.child("properties") is Some(element) {
    Properties::from_element(element).remove(property)
  }
}

///|
struct TestCase {
  element_ : Element
  flavor_ : Flavor
}

///|
pub fn TestCase::new(
  name~ : String? = None,
  classname~ : String? = None,
  time~ : Double? = None,
  flavor~ : Flavor = Base,
) -> TestCase raise JUnitError {
  let element_ = Element::new("testcase")
  element_.set_attribute("name", name)
  element_.set_attribute("classname", classname)
  if time is Some(time) {
    element_.set_float_attribute("time", time)
  }
  { element_, flavor_: flavor, }
}

///|
pub fn TestCase::from_element(
  element : Element,
  flavor~ : Flavor = Base,
) -> TestCase {
  { element_: element, flavor_: flavor, }
}

///|
pub fn TestCase::element(self : TestCase) -> Element {
  self.element_
}

///|
pub fn TestCase::flavor(self : TestCase) -> Flavor {
  self.flavor_
}

///|
pub fn TestCase::from_string(
  source : String,
  flavor~ : Flavor = Base,
) -> TestCase raise JUnitError {
  TestCase::from_element(Element::from_string(source), flavor~)
}

///|
pub fn TestCase::clone(self : TestCase) -> TestCase raise JUnitError {
  TestCase::from_element(self.element_.clone(), flavor=self.flavor_)
}

///|
pub fn TestCase::equal(
  self : TestCase,
  other : TestCase,
) -> Bool raise JUnitError {
  self.element_.comparison_key() == other.element_.comparison_key()
}

///|
/// Known result/output descendants, in document order, as in TestCase.__iter__.
pub fn TestCase::entries(self : TestCase) -> Iter[Element] {
  self.element_
  .iter()
  .filter(fn(node) {
    if !node.is_element() {
      return false
    }
    match result_kind(node.tag()) {
      Some(kind) => kind.is_final() || self.flavor_ == XUnit2
      None => node.tag() == "system-out" || node.tag() == "system-err"
    }
  })
}

///|
pub fn TestCase::results(self : TestCase) -> Array[TestResult] {
  let result = []
  for node in self.entries() {
    if result_kind(node.tag()) is Some(kind) && kind.is_final() {
      result.push(TestResult::from_element(node, kind))
    }
  }
  result
}

///|
pub fn TestCase::set_results(
  self : TestCase,
  results : Array[TestResult],
) -> Unit raise JUnitError {
  for result in results {
    if !result.kind_.is_final() {
      raise InvalidValue("expected a final result")
    }
  }
  for result in self.results() {
    for child in self.element_.iter_children(name=Some(result.kind_.tag())) {
      if TestResult::from_element(child, result.kind_).equal(result) {
        self.element_.remove_node(child)
      }
    }
  }
  for result in results {
    self.element_.append(result.element_)
  }
}

///|
pub fn TestCase::is_passed(self : TestCase) -> Bool {
  self.results().is_empty()
}

///|
pub fn TestCase::is_failure(self : TestCase) -> Bool {
  self.results().iter().any(r => r.kind_ == Failure)
}

///|
pub fn TestCase::is_error(self : TestCase) -> Bool {
  self.results().iter().any(r => r.kind_ == Error)
}

///|
pub fn TestCase::is_skipped(self : TestCase) -> Bool {
  self.results().iter().any(r => r.kind_ == Skipped)
}

///|
pub fn TestCase::interim_results(
  self : TestCase,
  kind~ : ResultKind? = None,
) -> Array[TestResult] {
  let result = []
  for node in self.entries() {
    if result_kind(node.tag()) is Some(found) &&
      !found.is_final() &&
      (kind == None || kind == Some(found)) {
      result.push(TestResult::from_element(node, found))
    }
  }
  result
}

///|
pub fn TestCase::add_interim_result(
  self : TestCase,
  result : TestResult,
) -> Unit raise JUnitError {
  self.element_.append(result.element_)
}

///|
pub fn TestCase::is_rerun(self : TestCase) -> Bool {
  self
  .interim_results()
  .iter()
  .any(r => r.kind_ == RerunFailure || r.kind_ == RerunError)
}

///|
pub fn TestCase::is_flaky(self : TestCase) -> Bool {
  self
  .interim_results()
  .iter()
  .any(r => r.kind_ == FlakyFailure || r.kind_ == FlakyError)
}

///|
struct TestSuite {
  element_ : Element
  flavor_ : Flavor
  mut filepath_ : String?
}

///|
pub fn TestSuite::new(
  name~ : String? = None,
  flavor~ : Flavor = Base,
) -> TestSuite raise JUnitError {
  let element_ = Element::new("testsuite")
  element_.set_attribute("name", name)
  { element_, flavor_: flavor, filepath_: None, }
}

///|
pub fn TestSuite::from_element(
  element : Element,
  flavor~ : Flavor = Base,
) -> TestSuite {
  { element_: element, flavor_: flavor, filepath_: None, }
}

///|
pub fn TestSuite::element(self : TestSuite) -> Element {
  self.element_
}

///|
pub fn TestSuite::flavor(self : TestSuite) -> Flavor {
  self.flavor_
}

///|
pub fn TestSuite::from_string(
  source : String,
  flavor~ : Flavor = Base,
) -> TestSuite raise JUnitError {
  TestSuite::from_element(Element::from_string(source), flavor~)
}

///|
pub fn TestSuite::clone(self : TestSuite) -> TestSuite raise JUnitError {
  let result = TestSuite::from_element(
    self.element_.clone(),
    flavor=self.flavor_,
  )
  result.filepath_ = self.filepath_
  result
}

///|
priv struct SuiteIterator {
  cases : Iter[Element]
  suites : Iter[Element]
  mut direct_done : Bool
}

///|
fn suite_iterator(node : Element) -> SuiteIterator {
  {
    cases: node.iter_children(name=Some("testcase")),
    suites: node.iter_children(name=Some("testsuite")),
    direct_done: false,
  }
}

///|
/// Direct cases first, then each nested suite recursively; handles stay live.
pub fn TestSuite::cases(self : TestSuite) -> Iter[TestCase] {
  let stack = [suite_iterator(self.element_)]
  Iter::new(fn() {
    while stack.last() is Some(frame) {
      if !frame.direct_done {
        if frame.cases.next() is Some(node) {
          return Some(TestCase::from_element(node, flavor=self.flavor_))
        }
        frame.direct_done = true
      }
      if frame.suites.next() is Some(node) {
        stack.push(suite_iterator(node))
      } else {
        ignore(stack.pop())
      }
    }
    None
  })
}

///|
pub fn TestSuite::len(self : TestSuite) -> Int32 {
  self.cases().count()
}

///|
pub fn TestSuite::suites(self : TestSuite) -> Iter[TestSuite] {
  self.element_
  .iter_children(name=Some("testsuite"))
  .map(node => TestSuite::from_element(node, flavor=self.flavor_))
}

///|
pub fn TestSuite::equal(
  self : TestSuite,
  other : TestSuite,
) -> Bool raise JUnitError {
  for key in ["name", "hostname", "timestamp"] {
    if self.element_.attribute(key) != other.element_.attribute(key) {
      return false
    }
  }
  let a = self.element_.properties().to_array()
  let b = other.element_.properties().to_array()
  if a.length() != b.length() {
    return false
  }
  let a = sorted_properties(a, false)
  let b = sorted_properties(b, false)
  for i = 0; i < a.length(); i = i + 1 {
    if !a[i].equal(b[i]) {
      return false
    }
  }
  true
}

///|
pub fn TestSuite::update_statistics(self : TestSuite) -> Unit raise JUnitError {
  let mut tests = 0
  let mut errors = 0
  let mut failures = 0
  let mut skipped = 0
  let mut time = 0.0
  let mut timed = false
  for case in self.cases() {
    tests += 1
    if tests > 1000000 {
      raise LimitExceeded("statistics exceeds 1000000 cases")
    }
    if case.element_.float_attribute("time") is Some(value) {
      time += value
      timed = true
    }
    for result in case.results() {
      match result.kind_ {
        Failure => failures += 1
        Error => errors += 1
        Skipped => skipped += 1
        _ => ()
      }
    }
  }
  self.element_.set_attribute("tests", Some(tests.to_string()))
  self.element_.set_attribute("errors", Some(errors.to_string()))
  self.element_.set_attribute("failures", Some(failures.to_string()))
  self.element_.set_attribute("skipped", Some(skipped.to_string()))
  self.element_.set_attribute(
    "time",
    Some(if timed { py_repr(py_round3(time)) } else { "0" }),
  )
}

///|
pub fn TestSuite::add_case(
  self : TestSuite,
  case : TestCase,
) -> Unit raise JUnitError {
  self.element_.append(case.element_)
  self.update_statistics()
}

///|
pub fn TestSuite::add_cases(
  self : TestSuite,
  cases : Array[TestCase],
) -> Unit raise JUnitError {
  for case in cases {
    self.element_.append(case.element_)
  }
  self.update_statistics()
}

///|
pub fn TestSuite::add_suite(
  self : TestSuite,
  suite : TestSuite,
) -> Unit raise JUnitError {
  self.element_.append(suite.element_)
}

///|
pub fn TestSuite::remove_case(
  self : TestSuite,
  case : TestCase,
) -> Unit raise JUnitError {
  for candidate in self.cases() {
    if candidate.equal(case) {
      for child in self.element_.iter_children(name=Some("testcase")) {
        if TestCase::from_element(child).equal(candidate) {
          self.element_.remove_node(child)
        }
      }
      self.update_statistics()
    }
  }
}

///|
struct JUnitXml {
  element_ : Element
  flavor_ : Flavor
  mut filepath_ : String?
  mut skipped_shadow_ : @bigint.BigInt?
}

///|
pub fn JUnitXml::new(
  name~ : String? = None,
  flavor~ : Flavor = Base,
) -> JUnitXml raise JUnitError {
  let element_ = Element::new("testsuites")
  element_.set_attribute("name", name)
  { element_, flavor_: flavor, filepath_: None, skipped_shadow_: None, }
}

///|
pub fn JUnitXml::from_root(
  element : Element,
  flavor~ : Flavor = Base,
) -> JUnitXml raise JUnitError {
  let root = if element.is_element() && element.tag() == "testsuite" {
    let wrapper = Element::new("testsuites")
    wrapper.state().defaults = element.state().defaults
    wrapper.state().doctype = element.state().doctype
    wrapper.state().pre_doctype = element.state().pre_doctype
    wrapper.append(element)
    wrapper
  } else {
    element
  }
  if !root.is_element() || root.tag() != "testsuites" {
    raise InvalidFormat("expected testsuite or testsuites")
  }
  { element_: root, flavor_: flavor, filepath_: None, skipped_shadow_: None, }
}

///|
pub fn JUnitXml::from_string(
  source : String,
  flavor~ : Flavor = Base,
) -> JUnitXml raise JUnitError {
  JUnitXml::from_root(Element::from_string(source), flavor~)
}

///|
/// Wrap an existing element without root validation (Element.fromelem).
pub fn JUnitXml::from_element(
  element : Element,
  flavor~ : Flavor = Base,
) -> JUnitXml {
  {
    element_: element,
    flavor_: flavor,
    filepath_: None,
    skipped_shadow_: None,
  }
}

///|
pub fn JUnitXml::from_decoded(
  source : String,
  flavor~ : Flavor = Base,
) -> JUnitXml raise JUnitError {
  JUnitXml::from_root(Element::from_decoded(source), flavor~)
}

///|
pub fn JUnitXml::element(self : JUnitXml) -> Element {
  self.element_
}

///|
pub fn JUnitXml::flavor(self : JUnitXml) -> Flavor {
  self.flavor_
}

///|
pub fn JUnitXml::clone(self : JUnitXml) -> JUnitXml raise JUnitError {
  let result = JUnitXml::from_root(self.element_.clone(), flavor=self.flavor_)
  result.filepath_ = self.filepath_
  result.skipped_shadow_ = self.skipped_shadow_
  result
}

///|
pub fn JUnitXml::suites(self : JUnitXml) -> Iter[TestSuite] {
  self.element_
  .iter_children(name=Some("testsuite"))
  .map(node => TestSuite::from_element(node, flavor=self.flavor_))
}

///|
pub fn JUnitXml::len(self : JUnitXml) -> Int32 {
  self.suites().count()
}

///|
pub fn JUnitXml::add_suite(
  self : JUnitXml,
  suite : TestSuite,
) -> Unit raise JUnitError {
  for existing in self.suites() {
    if existing.equal(suite) {
      // A snapshot also bounds self-add, which can otherwise loop forever in Python.
      for case in suite.cases().to_array() {
        existing.element_.append(case.element_)
      }
      return
    }
  }
  self.element_.append(suite.element_)
}

///|
pub fn JUnitXml::update_statistics(self : JUnitXml) -> Unit raise JUnitError {
  let mut tests = @bigint.BigInt::from_int(0)
  let mut failures = @bigint.BigInt::from_int(0)
  let mut errors = @bigint.BigInt::from_int(0)
  let mut skipped = @bigint.BigInt::from_int(0)
  let mut time = 0.0
  let mut timed = false
  for suite in self.suites() {
    suite.update_statistics()
    tests += suite.element_.int_attribute("tests").unwrap()
    failures += suite.element_.int_attribute("failures").unwrap()
    errors += suite.element_.int_attribute("errors").unwrap()
    if self.flavor_ == Base {
      skipped += suite.element_.int_attribute("skipped").unwrap()
    }
    time += suite.element_.float_attribute("time").unwrap()
    timed = true
  }
  self.element_.set_int_attribute("tests", tests)
  self.element_.set_int_attribute("failures", failures)
  self.element_.set_int_attribute("errors", errors)
  if self.flavor_ == Base {
    self.element_.set_int_attribute("skipped", skipped)
  }
  self.element_.set_attribute(
    "time",
    Some(if timed { py_repr(py_round3(time)) } else { "0" }),
  )
}

///|
pub fn JUnitXml::extend_suites(
  self : JUnitXml,
  suites : Iter[TestSuite],
) -> Unit raise JUnitError {
  let mut count = 0
  for suite in suites {
    count += 1
    if count > 1000000 {
      raise LimitExceeded("merge exceeds 1000000 suites")
    }
    self.add_suite(suite.clone())
  }
  self.update_statistics()
}

///|
pub fn JUnitXml::merge_inplace(
  self : JUnitXml,
  other : JUnitXml,
) -> Unit raise JUnitError {
  self.extend_suites(other.suites())
}

///|
/// Root += suite copies only its name and flattened cases, as junitparser does.
pub fn JUnitXml::merge_suite_inplace(
  self : JUnitXml,
  other : TestSuite,
) -> Unit raise JUnitError {
  let suite = TestSuite::new(
    name=other.element_.attribute("name"),
    flavor=self.flavor_,
  )
  for case in other.cases() {
    suite.element_.append(case.element_.clone())
  }
  self.add_suite(suite)
  self.update_statistics()
}

///|
/// Root + root starts a new root, without either input's root attributes.
pub fn JUnitXml::merged(
  self : JUnitXml,
  other : JUnitXml,
) -> JUnitXml raise JUnitError {
  let result = JUnitXml::new(flavor=self.flavor_)
  result.merge_inplace(self)
  result.merge_inplace(other)
  result
}

///|
pub fn JUnitXml::merged_suite(
  self : JUnitXml,
  other : TestSuite,
) -> JUnitXml raise JUnitError {
  let result = JUnitXml::new(flavor=self.flavor_)
  result.merge_inplace(self)
  result.merge_suite_inplace(other)
  result
}

///|
pub(all) enum SuiteMerge {
  Suite(TestSuite)
  Document(JUnitXml)
}

///|
pub fn TestSuite::merge_inplace(
  self : TestSuite,
  other : TestSuite,
) -> SuiteMerge raise JUnitError {
  if self.equal(other) {
    let cases = other.cases().to_array()
    for case in cases {
      self.element_.append(case.element_.clone())
    }
    let suites = other.suites().to_array()
    for suite in suites {
      self.add_suite(suite.clone())
    }
    self.update_statistics()
    Suite(self)
  } else {
    let result = JUnitXml::new(flavor=self.flavor_)
    result.filepath_ = self.filepath_
    result.add_suite(self)
    result.add_suite(other.clone())
    Document(result)
  }
}

///|
pub fn TestSuite::merged(
  self : TestSuite,
  other : TestSuite,
) -> SuiteMerge raise JUnitError {
  if self.equal(other) {
    self.clone().merge_inplace(other)
  } else {
    let result = JUnitXml::new(flavor=self.flavor_)
    result.add_suite(self.clone())
    result.add_suite(other.clone())
    Document(result)
  }
}
