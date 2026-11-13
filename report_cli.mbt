///|
// Unicode decimal-digit block starts (Unicode 15.1, CPython 3.13). Nd digits,
// not arbitrary numeric symbols, in float and integer strings.
fn report_digit(ch : Char) -> Int32? {
  let code = ch.to_int()
  for
    start in [
      0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6,
      0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0,
      0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620,
      0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10, 0x104A0, 0x10D30, 0x11066,
      0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650, 0x116C0, 0x11730,
      0x118E0, 0x11950, 0x11C50, 0x11D50, 0x11DA0, 0x11F50, 0x16A60, 0x16AC0, 0x16B50,
      0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0x1E140, 0x1E2F0, 0x1E4F0, 0x1E950,
      0x1FBF0,
    ] {
    if code >= start && code < start + 10 {
      return Some(code - start)
    }
  }
  None
}

///|
fn report_option(arg : String, command : String) -> Bool {
  if arg.has_prefix("--=") || arg.has_prefix("-=") {
    return true
  }
  if arg.has_prefix("-h") {
    return true
  }
  if arg.has_prefix("--") {
    let stem = arg.split("=").next().unwrap().to_owned()
    if stem.length() > 2 &&
      (
        "--help".has_prefix(stem) ||
        "--glob".has_prefix(stem) ||
        (command == "merge" && "--suite-name".has_prefix(stem))
      ) {
      return true
    }
  }
  if !arg.has_prefix("-") || arg == "-" || arg.contains(" ") {
    return false
  }
  let chars = arg.to_array()
  let length = chars.length() - (if chars.last() == Some('\n') { 1 } else { 0 })
  let mut digits = 0
  let mut dot = false
  for i = 1; i < length; i = i + 1 {
    if report_digit(chars[i]) is Some(_) {
      digits += 1
    } else if chars[i] == '.' && !dot {
      dot = true
      digits = 0
    } else {
      return true
    }
  }
  digits == 0
}

///|
fn report_usage(command : String) -> String {
  if command == "merge" {
    "Usage: junit-delta merge [--glob] [--suite-name NAME] INPUT... OUTPUT\nOUTPUT '-' writes UTF-8 XML to stdout.\n"
  } else {
    "Usage: junit-delta verify [--glob] INPUT...\nExit: 0 passed/skipped, 1 failed/error or runtime error, 2 usage error.\n"
  }
}

///|
fn run_report_cli(
  args : Array[String],
  read : (String) -> String raise,
  write~ : ((String, String) -> Unit raise)?,
  glob~ : ((String) -> Array[String] raise)?,
) -> CliResult {
  let command = args[0]
  let paths = []
  let mut use_glob = false
  let mut suite_name = None
  let mut options = true
  let mut limit = None
  let mut invalid = false
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if options &&
      (
        (arg.has_prefix("--=") || arg.has_prefix("-=")) ||
        (
          arg.has_prefix("-h") &&
          ({
            let chars = arg.to_array()
            let mut i = 1
            while i < chars.length() && chars[i] == 'h' {
              i += 1
            }
            i < chars.length() && (chars[i] == '=' || chars[i] == '-')
          })
        )
      ) {
      return { stdout: "", stderr: report_usage(command), status: 2, }
    }
    if options &&
      arg.has_prefix("--") &&
      arg.contains("=") &&
      arg.find("=").unwrap() > 2 &&
      (
        "--glob".has_prefix(arg[:arg.find("=").unwrap()].to_owned()) ||
        "--help".has_prefix(arg[:arg.find("=").unwrap()].to_owned())
      ) {
      return { stdout: "", stderr: report_usage(command), status: 2, }
    }
    if options &&
      (
        arg.has_prefix("-h") ||
        (arg.has_prefix("--") && "--help".has_prefix(arg) && arg.length() > 2)
      ) {
      return { stdout: report_usage(command), stderr: "", status: 0, }
    } else if options && arg == "--" {
      if limit is Some(maximum) && paths.length() >= maximum {
        invalid = true
      }
      options = false
    } else if options &&
      arg.has_prefix("--") &&
      arg.length() > 2 &&
      "--glob".has_prefix(arg) {
      if !paths.is_empty() && limit is None {
        limit = Some(
          if command == "merge" && paths.length() == 1 {
            2
          } else {
            paths.length()
          },
        )
      }
      use_glob = true
    } else if options &&
      command == "merge" &&
      arg.has_prefix("--") &&
      arg.contains("=") &&
      arg.find("=").unwrap() > 2 &&
      "--suite-name".has_prefix(arg.split("=").next().unwrap().to_owned()) {
      if !paths.is_empty() && limit is None {
        limit = Some(if paths.length() == 1 { 2 } else { paths.length() })
      }
      suite_name = Some(arg[arg.find("=").unwrap() + 1:].to_owned())
    } else if options &&
      command == "merge" &&
      arg.has_prefix("--") &&
      arg.length() > 2 &&
      "--suite-name".has_prefix(arg) {
      if !paths.is_empty() && limit is None {
        limit = Some(if paths.length() == 1 { 2 } else { paths.length() })
      }
      index += 1
      if index >= args.length() || report_option(args[index], command) {
        return {
          stdout: "",
          stderr: "junit-delta: --suite-name requires a value\n",
          status: 2,
        }
      }
      suite_name = Some(args[index])
    } else if options && report_option(arg, command) {
      invalid = true
    } else {
      if limit is Some(maximum) && paths.length() >= maximum {
        invalid = true
      }
      paths.push(arg)
    }
    index += 1
  }
  if invalid || paths.length() < (if command == "merge" { 2 } else { 1 }) {
    return { stdout: "", stderr: report_usage(command), status: 2, }
  }
  let output = if command == "merge" { paths.pop().unwrap() } else { "" }
  try {
    let result = @junit.JUnitXml::new()
    for pattern in paths {
      let sources = if use_glob {
        match glob {
          Some(glob) => glob(pattern)
          None =>
            raise InvalidInput("this host has not supplied glob expansion")
        }
      } else {
        [pattern]
      }
      for path in sources {
        let report = @junit.JUnitXml::from_decoded(read(path))
        if command == "verify" {
          for suite in report.suites() {
            for case in suite.cases() {
              if !case.is_passed() && !case.is_skipped() {
                return { stdout: "", stderr: "", status: 1, }
              }
            }
          }
        } else {
          result.merge_inplace(report)
        }
      }
    }
    if command == "verify" {
      return { stdout: "", stderr: "", status: 0, }
    }
    result.update_statistics()
    if suite_name is Some(name) && name != "" {
      result.set_name(Some(name))
    }
    let xml = result.element().write_xml()
    if output == "-" {
      return { stdout: xml, stderr: "", status: 0, }
    }
    match write {
      Some(write) => write(output, xml)
      None => raise InvalidInput("this host has not supplied file writing")
    }
    { stdout: "", stderr: "", status: 0, }
  } catch {
    error =>
      {
        stdout: "",
        stderr: "junit-delta: \{terminal_text(clipped(error.to_string(), 2048))}\n",
        status: 1,
      }
  }
}
