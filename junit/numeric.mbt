///|
// Unicode decimal-digit block starts (Unicode 15.1, CPython 3.13). Nd digits,
// not arbitrary numeric symbols, in float and integer strings.
fn numeric_digit(ch : Char) -> Int32? {
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
fn numeric_space(ch : Char) -> Bool {
  let c = ch.to_int()
  c == 32 ||
  (c >= 9 && c <= 13) ||
  c == 0x85 ||
  c == 0xA0 ||
  c == 0x1680 ||
  (c >= 0x2000 && c <= 0x200A) ||
  c == 0x2028 ||
  c == 0x2029 ||
  c == 0x202F ||
  c == 0x205F ||
  c == 0x3000
}

///|
fn numeric_normalize(text : String) -> String raise JUnitError {
  if text.length() > 10000000 {
    raise LimitExceeded("numeric input exceeds 10000000 units")
  }
  let chars = text.to_array()
  let mut first = 0
  let mut last = chars.length()
  while first < last && numeric_space(chars[first]) {
    first += 1
  }
  while last > first && numeric_space(chars[last - 1]) {
    last -= 1
  }
  let out = StringBuilder()
  for i = first; i < last; i = i + 1 {
    if chars[i] == '_' {
      if i == first ||
        i + 1 == last ||
        numeric_digit(chars[i - 1]) == None ||
        numeric_digit(chars[i + 1]) == None {
        raise InvalidValue("invalid numeric separator")
      }
      continue
    }
    match numeric_digit(chars[i]) {
      Some(digit) => out.write_char((48 + digit).unsafe_to_char())
      None => {
        if chars[i].to_int() > 127 {
          raise InvalidValue("invalid numeric character")
        }
        out.write_char(chars[i])
      }
    }
  }
  out.to_string()
}

///|
fn py_float(text : String) -> Double raise JUnitError {
  let text = numeric_normalize(text).to_lower()
  match text {
    "nan" | "+nan" => return 0x7ff8000000000000UL.reinterpret_as_double()
    "-nan" => return 0xfff8000000000000UL.reinterpret_as_double()
    "inf" | "+inf" | "infinity" | "+infinity" => return 1.0 / 0.0
    "-inf" | "-infinity" => return -1.0 / 0.0
    _ => ()
  }
  let chars = text.to_array()
  let mut i = 0
  let negative = !chars.is_empty() && chars[0] == '-'
  if !chars.is_empty() && (chars[0] == '-' || chars[0] == '+') {
    i += 1
  }
  let mut digits = 0
  let mut before_dot = 0
  let mut first_nonzero = -1
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    if chars[i] != '0' && first_nonzero < 0 {
      first_nonzero = digits
    }
    digits += 1
    before_dot += 1
    i += 1
  }
  if i < chars.length() && chars[i] == '.' {
    i += 1
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      if chars[i] != '0' && first_nonzero < 0 {
        first_nonzero = digits
      }
      digits += 1
      i += 1
    }
  }
  if digits == 0 {
    raise InvalidValue("invalid floating-point value")
  }
  let mantissa_end = i
  let mut exponent = 0
  let exponent_limit = chars.length() + 800
  if i < chars.length() && chars[i] == 'e' {
    i += 1
    let exp_negative = i < chars.length() && chars[i] == '-'
    if i < chars.length() && (chars[i] == '-' || chars[i] == '+') {
      i += 1
    }
    let start = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      exponent = (exponent * 10 + chars[i].to_int() - 48).min(exponent_limit)
      i += 1
    }
    if i == start {
      raise InvalidValue("missing floating-point exponent")
    }
    if exp_negative {
      exponent = -exponent
    }
  }
  if i != chars.length() {
    raise InvalidValue("invalid floating-point value")
  }
  let zero = if negative { -0.0 } else { 0.0 }
  if first_nonzero < 0 {
    return zero
  }
  let magnitude = before_dot - first_nonzero - 1 + exponent
  if magnitude > 308 {
    return if negative { -1.0 / 0.0 } else { 1.0 / 0.0 }
  }
  if magnitude < -324 {
    return zero
  }
  // Canonicalize compensating exponents and very long significands before
  // handing conversion to the standard library. Binary64 halfway values have
  // at most 768 significant decimal digits; 800 plus a sticky digit preserves
  // which side of every rounding boundary the original decimal occupies.
  let significant : Array[Char] = []
  let mut seen = 0
  let mut sticky = false
  for j = 0; j < mantissa_end; j = j + 1 {
    let ch = chars[j]
    if ch >= '0' && ch <= '9' {
      if seen >= first_nonzero {
        if significant.length() < 800 {
          significant.push(ch)
        } else if ch != '0' {
          sticky = true
        }
      }
      seen += 1
    }
  }
  if sticky {
    significant.push('1')
  } else {
    while significant.length() > 1 && significant.last() == Some('0') {
      ignore(significant.pop())
    }
  }
  if magnitude == -324 {
    // Decide the first two subnormal bins exactly, independently of the
    // standard converter's underflow error convention.
    let numerator = @bigint.BigInt::from_string(String::from_array(significant)) <<
      1075
    let denominator = @bigint.BigInt::from_int(10).pow(
      @bigint.BigInt::from_int(significant.length() - 1 - magnitude),
    )
    let bits = if numerator <= denominator {
      0UL
    } else if numerator < denominator * @bigint.BigInt::from_int(3) {
      1UL
    } else {
      2UL
    }
    return (bits | (if negative { 0x8000000000000000UL } else { 0UL })).reinterpret_as_double()
  }
  let canonical = (if negative { "-" } else { "" }) +
    significant[0].to_string() +
    (if significant.length() > 1 {
      "." + String::from_array(significant[1:].to_owned())
    } else {
      ""
    }) +
    "e" +
    magnitude.to_string()
  @string.parse_double(canonical[:]) catch {
    _ =>
      if magnitude == 308 {
        if negative {
          -1.0 / 0.0
        } else {
          1.0 / 0.0
        }
      } else {
        raise InvalidValue("floating-point conversion failed")
      }
  }
}

///|
// Round the exact binary64 value to three decimal places, ties to even.
// The significand times 125 fits UInt64; division by a power of two is exact.
// Beyond 2^43 the binary64 spacing exceeds twice the decimal rounding error.
fn py_round3(value : Double) -> Double {
  if !value.is_finite() || value == 0.0 || value.abs() >= 8796093022208.0 {
    return value
  }
  let bits = value.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent = ((bits >> 52) & 0x7ffUL).to_int()
  let significand = (bits & 0xfffffffffffffUL) +
    (if exponent == 0 { 0UL } else { 0x10000000000000UL })
  let shift = 1072 - (if exponent == 0 { 1 } else { exponent })
  if shift >= 64 {
    return if negative { -0.0 } else { 0.0 }
  }
  let scaled = significand * 125UL
  let mut rounded = scaled >> shift
  let remainder = scaled & ((1UL << shift) - 1UL)
  let half = 1UL << (shift - 1)
  if remainder > half || (remainder == half && (rounded & 1UL) != 0UL) {
    rounded += 1UL
  }
  let result = rounded.to_double() / 1000.0
  if negative {
    -result
  } else {
    result
  }
}

///|
// Reformat the standard library's shortest round-trip digits using Python's
// fixed/scientific thresholds, explicit float suffix and exponent spelling.
fn py_repr(value : Double) -> String {
  if value.is_nan() {
    return "nan"
  }
  if value.is_pos_inf() {
    return "inf"
  }
  if value.is_neg_inf() {
    return "-inf"
  }
  let sign = if value.reinterpret_as_uint64() >> 63 != 0UL { "-" } else { "" }
  if value == 0.0 {
    return sign + "0.0"
  }
  let raw = value.abs().to_string().to_lower()
  let parts = raw.split("e").map(s => s.to_owned()).to_array()
  let mut exponent = 0
  if parts.length() == 2 {
    let negative = parts[1].has_prefix("-")
    let chars = parts[1].to_array()
    let start = if chars[0] == '-' || chars[0] == '+' { 1 } else { 0 }
    for i = start; i < chars.length(); i = i + 1 {
      if chars[i] < '0' || chars[i] > '9' {
        abort("invalid standard-library float exponent")
      }
      exponent = exponent * 10 + chars[i].to_int() - 48
    }
    if negative {
      exponent = -exponent
    }
  }
  let digits = StringBuilder()
  let mut point = false
  let mut point_position = 0
  for ch in parts[0] {
    if ch == '.' {
      point = true
    } else {
      digits.write_char(ch)
      if !point {
        point_position += 1
      }
    }
  }
  let text = digits.to_string().to_array()
  let mut start = 0
  while start < text.length() && text[start] == '0' {
    start += 1
  }
  let mut end = text.length()
  while end > start + 1 && text[end - 1] == '0' {
    end -= 1
  }
  exponent += point_position - start - 1
  let significant = String::from_array(text[start:end].to_owned())
  let length = significant.length()
  if exponent >= -4 && exponent < 16 {
    if exponent < 0 {
      sign + "0." + String::make(-exponent - 1, '0') + significant
    } else if exponent + 1 >= length {
      sign + significant + String::make(exponent + 1 - length, '0') + ".0"
    } else {
      sign +
      significant[:exponent + 1].to_owned() +
      "." +
      significant[exponent + 1:].to_owned()
    }
  } else {
    let fraction = if length == 1 {
      ""
    } else {
      "." + significant[1:].to_owned()
    }
    let power = exponent.abs().to_string()
    sign +
    significant[:1].to_owned() +
    fraction +
    "e" +
    (if exponent < 0 { "-" } else { "+" }) +
    (if power.length() < 2 { "0" } else { "" }) +
    power
  }
}

///|
fn py_float_attr(value : String?) -> Double? raise JUnitError {
  match value {
    None | Some("") => None
    Some(text) => Some(py_float(text.replace_all(old=",", new="")))
  }
}

///|
fn py_int(text : String) -> @bigint.BigInt raise JUnitError {
  let normalized = numeric_normalize(text)
  let chars = normalized.to_array()
  let start = if !chars.is_empty() && (chars[0] == '+' || chars[0] == '-') {
    1
  } else {
    0
  }
  if chars.length() == start {
    raise InvalidValue("invalid integer")
  }
  if chars.length() - start > 4300 {
    raise InvalidValue("integer exceeds 4300 decimal digits")
  }
  for i = start; i < chars.length(); i = i + 1 {
    if chars[i] < '0' || chars[i] > '9' {
      raise InvalidValue("invalid integer")
    }
  }
  let digits = String::from_array(chars[start:].to_owned())
  let value = @bigint.BigInt::from_string(digits)
  if chars[0] == '-' {
    -value
  } else {
    value
  }
}
