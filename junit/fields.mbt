// Portions adapted from junitparser 5.0.3.
// Copyright 2025 Weiwei Wang.
// MoonBit adaptation and additions: 2026 tc-adventureking.
// SPDX-License-Identifier: Apache-2.0
// See third_party/junitparser-LICENSE and third_party/NOTICE.md.

///|
pub fn TestResult::message(self : TestResult) -> String? {
  self.element_.attribute("message")
}

///|
pub fn TestResult::set_message(
  self : TestResult,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("message", value)
}

///|
pub fn TestResult::type_(self : TestResult) -> String? {
  self.element_.attribute("type")
}

///|
pub fn TestResult::set_type_(
  self : TestResult,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("type", value)
}

///|
pub fn Property::name(self : Property) -> String? {
  self.element_.attribute("name")
}

///|
pub fn Property::set_name(
  self : Property,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("name", value)
}

///|
pub fn Property::value(self : Property) -> String? {
  self.element_.attribute("value")
}

///|
pub fn Property::set_value(
  self : Property,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("value", value)
}

///|
pub fn TestCase::name(self : TestCase) -> String? {
  self.element_.attribute("name")
}

///|
pub fn TestCase::set_name(
  self : TestCase,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("name", value)
}

///|
pub fn TestCase::classname(self : TestCase) -> String? {
  self.element_.attribute("classname")
}

///|
pub fn TestCase::set_classname(
  self : TestCase,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("classname", value)
}

///|
pub fn TestCase::group(self : TestCase) -> String? {
  self.element_.attribute("group")
}

///|
pub fn TestCase::set_group(
  self : TestCase,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("group", value)
}

///|
pub fn TestSuite::name(self : TestSuite) -> String? {
  self.element_.attribute("name")
}

///|
pub fn TestSuite::set_name(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("name", value)
}

///|
pub fn TestSuite::hostname(self : TestSuite) -> String? {
  self.element_.attribute("hostname")
}

///|
pub fn TestSuite::set_hostname(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("hostname", value)
}

///|
pub fn TestSuite::timestamp(self : TestSuite) -> String? {
  self.element_.attribute("timestamp")
}

///|
pub fn TestSuite::set_timestamp(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("timestamp", value)
}

///|
pub fn TestSuite::group(self : TestSuite) -> String? {
  self.element_.attribute("group")
}

///|
pub fn TestSuite::set_group(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("group", value)
}

///|
pub fn TestSuite::id(self : TestSuite) -> String? {
  self.element_.attribute("id")
}

///|
pub fn TestSuite::set_id(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("id", value)
}

///|
pub fn TestSuite::package_(self : TestSuite) -> String? {
  self.element_.attribute("package")
}

///|
pub fn TestSuite::set_package_(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("package", value)
}

///|
pub fn TestSuite::file(self : TestSuite) -> String? {
  self.element_.attribute("file")
}

///|
pub fn TestSuite::set_file(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("file", value)
}

///|
pub fn TestSuite::log(self : TestSuite) -> String? {
  self.element_.attribute("log")
}

///|
pub fn TestSuite::set_log(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("log", value)
}

///|
pub fn TestSuite::url(self : TestSuite) -> String? {
  self.element_.attribute("url")
}

///|
pub fn TestSuite::set_url(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("url", value)
}

///|
pub fn TestSuite::version(self : TestSuite) -> String? {
  self.element_.attribute("version")
}

///|
pub fn TestSuite::set_version(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("version", value)
}

///|
pub fn JUnitXml::name(self : JUnitXml) -> String? {
  self.element_.attribute("name")
}

///|
pub fn JUnitXml::set_name(
  self : JUnitXml,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_attribute("name", value)
}

///|
pub fn TestCase::time(self : TestCase) -> Double? raise JUnitError {
  self.element_.float_attribute("time")
}

///|
pub fn TestCase::set_time(
  self : TestCase,
  value : Double,
) -> Unit raise JUnitError {
  self.element_.set_float_attribute("time", value)
}

///|
pub fn TestCase::set_time_int(
  self : TestCase,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("time", value)
}

///|
pub fn TestSuite::time(self : TestSuite) -> Double? raise JUnitError {
  if self.element_.attribute("time") is None {
    self.update_statistics()
  }
  self.element_.float_attribute("time")
}

///|
pub fn TestSuite::set_time(
  self : TestSuite,
  value : Double,
) -> Unit raise JUnitError {
  self.element_.set_float_attribute("time", value)
}

///|
pub fn TestSuite::set_time_int(
  self : TestSuite,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("time", value)
}

///|
pub fn JUnitXml::time(self : JUnitXml) -> Double? raise JUnitError {
  if self.element_.attribute("time") is None {
    self.update_statistics()
  }
  self.element_.float_attribute("time")
}

///|
pub fn JUnitXml::set_time(
  self : JUnitXml,
  value : Double,
) -> Unit raise JUnitError {
  self.element_.set_float_attribute("time", value)
}

///|
pub fn JUnitXml::set_time_int(
  self : JUnitXml,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("time", value)
}

///|
pub fn TestSuite::tests(self : TestSuite) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("tests") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("tests")
}

///|
pub fn TestSuite::set_tests(
  self : TestSuite,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("tests", value)
}

///|
pub fn TestSuite::failures(
  self : TestSuite,
) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("failures") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("failures")
}

///|
pub fn TestSuite::set_failures(
  self : TestSuite,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("failures", value)
}

///|
pub fn TestSuite::errors(self : TestSuite) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("errors") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("errors")
}

///|
pub fn TestSuite::set_errors(
  self : TestSuite,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("errors", value)
}

///|
pub fn TestSuite::skipped(self : TestSuite) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("skipped") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("skipped")
}

///|
pub fn TestSuite::set_skipped(
  self : TestSuite,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("skipped", value)
}

///|
pub fn TestSuite::filepath(self : TestSuite) -> String? {
  self.filepath_
}

///|
pub fn TestSuite::set_filepath(self : TestSuite, path : String?) -> Unit {
  self.filepath_ = path
}

///|
pub fn TestSuite::int_attribute(
  self : TestSuite,
  name : String,
) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute(name) is None {
    self.update_statistics()
  }
  self.element_.int_attribute(name)
}

///|
pub fn TestSuite::float_attribute(
  self : TestSuite,
  name : String,
) -> Double? raise JUnitError {
  if self.element_.attribute(name) is None {
    self.update_statistics()
  }
  self.element_.float_attribute(name)
}

///|
pub fn JUnitXml::tests(self : JUnitXml) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("tests") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("tests")
}

///|
pub fn JUnitXml::set_tests(
  self : JUnitXml,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("tests", value)
}

///|
pub fn JUnitXml::failures(self : JUnitXml) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("failures") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("failures")
}

///|
pub fn JUnitXml::set_failures(
  self : JUnitXml,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("failures", value)
}

///|
pub fn JUnitXml::errors(self : JUnitXml) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute("errors") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("errors")
}

///|
pub fn JUnitXml::set_errors(
  self : JUnitXml,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  self.element_.set_int_attribute("errors", value)
}

///|
pub fn JUnitXml::skipped(self : JUnitXml) -> @bigint.BigInt? raise JUnitError {
  if self.flavor_ == XUnit2 {
    return self.skipped_shadow_
  }
  if self.element_.attribute("skipped") is None {
    self.update_statistics()
  }
  self.element_.int_attribute("skipped")
}

///|
pub fn JUnitXml::set_skipped(
  self : JUnitXml,
  value : @bigint.BigInt,
) -> Unit raise JUnitError {
  if self.flavor_ == XUnit2 {
    self.skipped_shadow_ = Some(value)
  } else {
    self.element_.set_int_attribute("skipped", value)
  }
}

///|
pub fn JUnitXml::filepath(self : JUnitXml) -> String? {
  self.filepath_
}

///|
pub fn JUnitXml::set_filepath(self : JUnitXml, path : String?) -> Unit {
  self.filepath_ = path
}

///|
pub fn JUnitXml::int_attribute(
  self : JUnitXml,
  name : String,
) -> @bigint.BigInt? raise JUnitError {
  if self.element_.attribute(name) is None {
    self.update_statistics()
  }
  self.element_.int_attribute(name)
}

///|
pub fn JUnitXml::float_attribute(
  self : JUnitXml,
  name : String,
) -> Double? raise JUnitError {
  if self.element_.attribute(name) is None {
    self.update_statistics()
  }
  self.element_.float_attribute(name)
}

///|
pub fn TestResult::system_out(self : TestResult) -> String? {
  self.element_.output("system-out")
}

///|
pub fn TestResult::set_system_out(
  self : TestResult,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("system-out", value)
}

///|
pub fn TestResult::system_err(self : TestResult) -> String? {
  self.element_.output("system-err")
}

///|
pub fn TestResult::set_system_err(
  self : TestResult,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("system-err", value)
}

///|
pub fn TestResult::stack_trace(self : TestResult) -> String? {
  self.element_.output("stackTrace")
}

///|
pub fn TestResult::set_stack_trace(
  self : TestResult,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("stackTrace", value)
}

///|
pub fn TestCase::system_out(self : TestCase) -> String? {
  self.element_.output("system-out")
}

///|
pub fn TestCase::set_system_out(
  self : TestCase,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("system-out", value)
}

///|
pub fn TestCase::system_err(self : TestCase) -> String? {
  self.element_.output("system-err")
}

///|
pub fn TestCase::set_system_err(
  self : TestCase,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("system-err", value)
}

///|
pub fn TestSuite::system_out(self : TestSuite) -> String? {
  self.element_.output("system-out")
}

///|
pub fn TestSuite::set_system_out(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("system-out", value)
}

///|
pub fn TestSuite::system_err(self : TestSuite) -> String? {
  self.element_.output("system-err")
}

///|
pub fn TestSuite::set_system_err(
  self : TestSuite,
  value : String?,
) -> Unit raise JUnitError {
  self.element_.set_output("system-err", value)
}

///|
pub fn TestCase::properties(self : TestCase) -> Iter[Property] {
  self.element_.properties()
}

///|
pub fn TestCase::add_property(
  self : TestCase,
  name : String,
  value : String,
) -> Unit raise JUnitError {
  self.element_.add_property(name, value)
}

///|
pub fn TestCase::remove_property(
  self : TestCase,
  property : Property,
) -> Unit raise JUnitError {
  self.element_.remove_property(property)
}

///|
pub fn TestSuite::properties(self : TestSuite) -> Iter[Property] {
  self.element_.properties()
}

///|
pub fn TestSuite::add_property(
  self : TestSuite,
  name : String,
  value : String,
) -> Unit raise JUnitError {
  self.element_.add_property(name, value)
}

///|
pub fn TestSuite::remove_property(
  self : TestSuite,
  property : Property,
) -> Unit raise JUnitError {
  self.element_.remove_property(property)
}

///|
pub fn TestCase::rerun_failures(self : TestCase) -> Array[TestResult] {
  self.interim_results(kind=Some(RerunFailure))
}

///|
pub fn TestCase::rerun_errors(self : TestCase) -> Array[TestResult] {
  self.interim_results(kind=Some(RerunError))
}

///|
pub fn TestCase::flaky_failures(self : TestCase) -> Array[TestResult] {
  self.interim_results(kind=Some(FlakyFailure))
}

///|
pub fn TestCase::flaky_errors(self : TestCase) -> Array[TestResult] {
  self.interim_results(kind=Some(FlakyError))
}

///|
pub fn JUnitXml::clear_skipped(self : JUnitXml) -> Unit raise JUnitError {
  if self.flavor_ != XUnit2 {
    raise InvalidValue("base skipped requires an integer")
  }
  self.skipped_shadow_ = None
}
