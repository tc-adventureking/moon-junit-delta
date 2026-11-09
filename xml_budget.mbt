///|
// A linear resource preflight, not an XML validator. The mature reader still
// validates all syntax. Bound its quadratic duplicate-attribute lookup before
// it starts; never inspect markup-looking text inside comments, CDATA or PIs.
fn check_xml_attribute_budget(text : String) -> Unit raise InputError {
  let mut mode = 0
  let mut attributes = 0
  let mut i = 0
  while i < text.length() {
    let ch = text[i].to_int()
    let next = if i + 1 < text.length() { text[i + 1].to_int() } else { -1 }
    let third = if i + 2 < text.length() { text[i + 2].to_int() } else { -1 }
    match mode {
      0 =>
        if ch == 60 {
          if next == 63 {
            mode = 6
            i = i + 1
          } else if next == 33 {
            if third == 45 && i + 3 < text.length() && text[i + 3] == 45 {
              mode = 4
              i = i + 3
            } else if i + 9 <= text.length() && text[i:i + 9] == "<![CDATA[" {
              mode = 5
              i = i + 8
            } else if i + 9 <= text.length() && text[i:i + 9] == "<!DOCTYPE" {
              raise Rejected("doctype", "DOCTYPE is unsupported")
            } else {
              raise Rejected("malformed_xml", "invalid XML declaration")
            }
          } else {
            mode = 1
            attributes = 0
          }
        }
      1 =>
        match ch {
          62 => mode = 0
          39 => mode = 2
          34 => mode = 3
          61 => {
            attributes = attributes + 1
            if attributes > 1024 {
              raise Rejected(
                "limit_exceeded", "XML element exceeds 1024 attributes",
              )
            }
          }
          _ => ()
        }
      2 => if ch == 39 { mode = 1 }
      3 => if ch == 34 { mode = 1 }
      4 =>
        if ch == 45 && next == 45 && third == 62 {
          mode = 0
          i = i + 2
        }
      5 =>
        if ch == 93 && next == 93 && third == 62 {
          mode = 0
          i = i + 2
        }
      _ =>
        if ch == 63 && next == 62 {
          mode = 0
          i = i + 1
        }
    }
    i = i + 1
  }
}
