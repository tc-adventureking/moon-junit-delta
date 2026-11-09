///|
// Measure compact JSON without allocating escaped copies of long source labels.
fn string_json_units(text : String) -> Int64 {
  let mut units = 2L
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i]
    units = units +
      (match ch.to_int() {
        8 | 9 | 10 | 12 | 13 | 34 | 92 => 2L
        c if c < 32 => 6L
        _ => 1L
      })
  }
  units
}

///|
fn json_units(value : Json) -> Int64 {
  match value {
    String(s) => string_json_units(s)
    Array(items) => {
      let mut n = 2L
      for i = 0; i < items.length(); i = i + 1 {
        n = n + json_units(items[i]) + (if i == 0 { 0L } else { 1L })
      }
      n
    }
    Object(fields) => {
      let mut n = 2L
      let mut first = true
      for key, value in fields {
        n = n +
          string_json_units(key) +
          1L +
          json_units(value) +
          (if first { 0L } else { 1L })
        first = false
      }
      n
    }
    _ => value.stringify().length().to_int64()
  }
}

///|
priv struct OutputBudget {
  maximum : Int64
  mut used : Int64
}

///|
fn output_budget(maximum : Int64) -> OutputBudget raise InputError {
  if maximum < 0L || maximum > 100000000L {
    raise Rejected(
      "output_limit", "output budget must be 0..100000000 UTF-16 units",
    )
  }
  { maximum, used: 0L, }
}

///|
fn OutputBudget::add(
  self : OutputBudget,
  units : Int64,
) -> Unit raise InputError {
  if units < 0L || units > self.maximum - self.used {
    raise Rejected(
      "output_limit",
      "rendered output exceeds \{self.maximum} UTF-16 units",
    )
  }
  self.used = self.used + units
}

///|
fn safe_units(text : String) -> Int64 {
  let mut units = 0L
  for ch in text {
    units = units +
      (match ch {
        '&' | '`' | '[' | ']' | '*' | '_' | '$' | '\\' => 5L
        '<' | '>' => 4L
        '|' | '~' => 6L
        '\n' | '\r' | '\t' => 1L
        _ =>
          if ch.to_int() < 32 || (ch.to_int() >= 127 && ch.to_int() <= 159) {
            0L
          } else if ch.to_int() > 65535 {
            2L
          } else {
            1L
          }
      })
  }
  units
}

///|
fn terminal_units(text : String) -> Int64 {
  let mut units = 0L
  for ch in text {
    units = units +
      (if ch.to_int() < 32 || (ch.to_int() >= 127 && ch.to_int() <= 159) {
        6L
      } else if ch.to_int() > 65535 {
        2L
      } else {
        1L
      })
  }
  units
}

///|
// Bounded diagnostic context, even when a shared suite name is very large.
fn TestId::preview(self : TestId) -> String {
  match self {
    Class(classname, name) =>
      "class " + clipped(classname, 80) + "/" + clipped(name, 80)
    SuitePath(path, name) => {
      let parts : Array[String] = []
      for part in path {
        if parts.length() >= 3 {
          break
        }
        parts.push(clipped(part, 48))
      }
      "suite " +
      parts.join("/") +
      (if path.length() > 3 { "/…" } else { "" }) +
      "/" +
      clipped(name, 80)
    }
  }
}

///|
fn clipped(text : String, limit : Int32) -> String {
  if text.length() <= limit {
    text
  } else {
    truncate_utf16(text, limit - 1) + "…"
  }
}
