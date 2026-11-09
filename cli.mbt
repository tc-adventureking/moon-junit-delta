///|
pub struct CliResult {
  stdout : String
  stderr : String
  status : Int32
}

///|
pub fn usage() -> String {
  let text =
    #|Usage: junit-delta compare --baseline BASE.xml [--baseline OLDER-TO-NEWER.xml ...]
    #|                          --candidate CURRENT.xml [--candidate SHARD.xml ...]
    #|                          [--format json|md|text] [--duplicates error|attempts]
    #|                          [--fail-on LIST|none] [--slowdown-pct 50]
    #|                          [--slowdown-floor-ms 200] [--limit 50]
    #|       junit-delta jsonl
    #|       junit-delta --help | --version
    #|
    #|Repeated baselines are chronological runs, not shards. Candidates are current-run shards.
    #|JSONL reads one request per line from stdin. '-' reads stdin once in compare mode.
    #|Gate names: new_failure,added_failing,still_failing,removed,newly_skipped,flaky,slowdown,empty_report
    #|Default gates: new_failure,added_failing,removed,empty_report.
    #|Exit: 0 pass, 1 gate violation, 2 input/usage error. Local tool: no network calls.
    #|
  text
}

///|
fn uint_arg(text : String, maximum : Int64) -> Int64 raise InputError {
  if text == "" {
    raise InvalidInput("expected an unsigned integer")
  }
  let mut value = 0L
  for c in text {
    if c < '0' || c > '9' {
      raise InvalidInput("expected unsigned integer: \{text}")
    }
    let digit = (c.to_int() - 48).to_int64()
    if value > (maximum - digit) / 10L {
      raise InvalidInput("integer exceeds \{maximum}")
    }
    value = value * 10L + digit
    if value > maximum {
      raise InvalidInput("integer exceeds \{maximum}")
    }
  }
  value
}

///|
/// The callback owns all I/O. This function can be tested on any MoonBit target.
pub fn run_cli(
  args : Array[String],
  read : (String) -> String raise,
) -> CliResult {
  try {
    if args == ["--help"] || args == ["-h"] {
      return { stdout: usage(), stderr: "", status: 0, }
    }
    if args == ["--version"] {
      return {
        stdout: "junit-delta \{release_version}\n",
        stderr: "",
        status: 0,
      }
    }
    if args == ["jsonl"] {
      let input = read("-")
      if input.length() > 20000000 {
        raise InvalidInput("JSONL input limit exceeded")
      }
      let out = StringBuilder()
      let mut status = 0
      let mut output_units = 0
      let mut line_number = 0
      for line in input.split("\n") {
        line_number = line_number + 1
        if line.trim().is_empty() {
          continue
        }
        let result = evaluate_request(line.to_owned())
        let code = integer_field(result, "exit_code", 2L, 2L).to_int()
        if code > status {
          status = code
        }
        let rendered = result.stringify() + "\n"
        if rendered.length() > 100000000 - output_units - 512 {
          out.write_string(
            (
              {
                "ok": false,
                "exit_code": 2,
                "error_code": "output_limit",
                "error": "JSONL output limit exceeded; remaining lines were not processed",
                "line": Json(line_number),
              } : Json).stringify() +
            "\n",
          )
          status = 2
          break
        }
        output_units = output_units + rendered.length()
        out.write_string(rendered)
      }
      return { stdout: out.to_string(), stderr: "", status, }
    }
    if args.is_empty() || args[0] != "compare" {
      raise InvalidInput(usage())
    }
    let bases : Array[String] = []
    let candidates : Array[String] = []
    let seen : Map[String, Bool] = Map([])
    let mut format = "text"
    let mut duplicates = Reject
    let mut fail_on = default_config().fail_on.iter().to_array()
    let mut pct = 50
    let mut floor_us = 200000L
    let mut limit = 50
    let mut i = 1
    while i < args.length() {
      let option = args[i]
      if i + 1 >= args.length() {
        raise InvalidInput("missing value for \{option}")
      }
      let value = args[i + 1]
      if option != "--baseline" && option != "--candidate" {
        if seen.contains(option) {
          raise InvalidInput("repeated option \{option}")
        }
        seen[option] = true
      }
      match option {
        "--baseline" => bases.push(value)
        "--candidate" => candidates.push(value)
        "--format" => format = value
        "--duplicates" => duplicates = parse_duplicates(value)
        "--fail-on" =>
          fail_on = if value == "none" {
            []
          } else {
            value.split(",").map(s => s.to_owned()).collect()
          }
        "--slowdown-pct" => pct = uint_arg(value, 1000000L).to_int()
        "--slowdown-floor-ms" => floor_us = uint_arg(value, 9000000000L) * 1000L
        "--limit" => limit = uint_arg(value, 100000L).to_int()
        _ => raise InvalidInput("unknown option: \{option}")
      }
      i = i + 2
    }
    if bases.is_empty() ||
      bases.length() > 50 ||
      candidates.is_empty() ||
      candidates.length() > 50 {
      raise InvalidInput("provide 1..50 baselines and 1..50 candidates")
    }
    if format != "json" && format != "md" && format != "text" {
      raise InvalidInput("format must be json, md or text")
    }
    let config = diff_config(
      slowdown_pct=pct,
      slowdown_floor_us=floor_us,
      fail_on~,
    )
    let mut stdin_seen = false
    let mut total = 0
    let load = fn(path : String) -> Report raise {
      if path == "-" {
        if stdin_seen {
          raise InvalidInput("stdin may only be used once")
        }
        stdin_seen = true
      }
      let content = read(path)
      total = total + content.length()
      if total > 20000000 {
        raise InvalidInput("combined XML input limit exceeded")
      }
      parse_report(content, source=path, duplicates~)
    }
    let history = bases.map(load)
    let candidate = merge_reports(candidates.map(load), duplicates~)
    let result = compare(history, candidate, config~)
    let stdout = match format {
      "json" => result.to_json_string() + "\n"
      "md" => result.to_markdown(limit~)
      _ => result.to_text()
    }
    { stdout, stderr: "", status: result.exit_code(), }
  } catch {
    error =>
      {
        stdout: "",
        stderr: "junit-delta: " +
        terminal_text(clipped(error.to_string(), 2048)) +
        "\n",
        status: 2,
      }
  }
}
