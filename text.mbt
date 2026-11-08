///|
/// Keep a complete UTF-16 prefix, never half of a supplementary character.
fn truncate_utf16(text : String, limit : Int32) -> String {
  if limit <= 0 {
    return ""
  }
  let mut n = if text.length() > limit { limit } else { text.length() }
  if n < text.length() && text[n - 1] >= 0xD800 && text[n - 1] <= 0xDBFF {
    n = n - 1
  }
  text[:n].to_owned()
}

///|
fn terminal_text(text : String) -> String {
  let builder = StringBuilder()
  for ch in text {
    let code = ch.to_int()
    if code < 32 || (code >= 127 && code <= 159) {
      let hex = code.to_string(radix=16)
      builder.write_string("\\u" + "0".repeat(4 - hex.length()) + hex)
    } else {
      builder.write_char(ch)
    }
  }
  builder.to_string()
}
