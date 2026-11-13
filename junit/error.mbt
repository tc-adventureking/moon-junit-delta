///|
/// Errors in JUnit document operations. Host I/O errors remain caller-owned.
#derive(Eq)
pub(all) suberror JUnitError {
  InvalidFormat(String)
  InvalidValue(String)
  ParseError(String)
  MissingFile
  LimitExceeded(String)
}

///|
pub extend JUnitError with Eq::{equal, not_equal}

///|
pub extend JUnitError with Show::{output, to_string}

///|
pub impl Show for JUnitError with fn output(self, logger) {
  match self {
    InvalidFormat(message) =>
      logger.write_string("invalid JUnit format: " + message)
    InvalidValue(message) => logger.write_string("invalid value: " + message)
    ParseError(message) => logger.write_string("XML parse error: " + message)
    MissingFile => logger.write_string("missing file argument")
    LimitExceeded(message) => logger.write_string("limit exceeded: " + message)
  }
}
