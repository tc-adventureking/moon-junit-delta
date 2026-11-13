// Portions adapted from junitparser 5.0.3.
// Copyright 2025 Weiwei Wang.
// MoonBit adaptation and additions: 2026 tc-adventureking.
// SPDX-License-Identifier: Apache-2.0
// See third_party/junitparser-LICENSE and third_party/NOTICE.md.

///|
fn utf8_bytes(text : String) -> Bytes {
  @utf8.encode(text[:])
}

///|
fn decode_xml(bytes : Bytes) -> String raise JUnitError {
  if bytes.length() > 20000000 {
    raise LimitExceeded("XML exceeds 20000000 bytes")
  }
  let utf16 = bytes.length() >= 2 &&
    (
      (bytes[0] == b'\xFF' && bytes[1] == b'\xFE') ||
      (bytes[0] == b'\xFE' && bytes[1] == b'\xFF')
    )
  let wide_le = bytes.length() >= 4 &&
    bytes[0] == b'<' &&
    bytes[1] == b'\x00' &&
    bytes[2] == b'?' &&
    bytes[3] == b'\x00'
  let wide_be = bytes.length() >= 4 &&
    bytes[0] == b'\x00' &&
    bytes[1] == b'<' &&
    bytes[2] == b'\x00' &&
    bytes[3] == b'?'
  if utf16 || wide_le || wide_be {
    let big_endian = wide_be ||
      (bytes.length() >= 2 && bytes[0] == b'\xFE' && bytes[1] == b'\xFF')
    return "\u{FEFF}" +
      (@utf16.decode(
        bytes[:],
        ignore_bom=true,
        endianness=if big_endian { Big } else { Little },
      ) catch {
        _ => raise ParseError("malformed UTF-16 XML")
      })
  }
  let text = @utf8.decode(bytes[:]) catch {
    _ =>
      raise ParseError(
        "malformed UTF-8 XML; supply a decoder for another encoding",
      )
  }
  let first = @xml.Reader::from_string(text).read_event() catch {
    error => raise ParseError(error.to_string())
  }
  if first.kind is Decl(encoding=Some(encoding), ..) {
    let encoding = encoding
      .to_upper()
      .replace_all(old="-", new="")
      .replace_all(old="_", new="")
    if encoding == "ASCII" || encoding == "USASCII" {
      for ch in text {
        if ch.to_int() > 127 && ch != '\u{FEFF}' {
          raise ParseError("non-ASCII character in ASCII XML")
        }
      }
    } else if encoding != "UTF8" {
      raise ParseError("XML encoding requires an explicit decoder: \{encoding}")
    }
  }
  text
}

///|
/// UTF-8/UTF-16 input. A decoder callback supports additional host encodings.
pub fn Element::from_bytes(
  bytes : Bytes,
  decode~ : ((Bytes) -> String raise)? = None,
) -> Element raise {
  let text = match decode {
    Some(decode) => decode(bytes)
    None => decode_xml(bytes)
  }
  Element::from_decoded(text)
}

///|
pub fn JUnitXml::from_bytes(
  bytes : Bytes,
  flavor~ : Flavor = Base,
  decode~ : ((Bytes) -> String raise)? = None,
) -> JUnitXml raise {
  JUnitXml::from_root(Element::from_bytes(bytes, decode~), flavor~)
}

///|
/// Read a path or URL through a host-supplied loader. The path is retained on
/// this document view, so write() can overwrite the same destination later.
pub fn JUnitXml::from_file(
  path : String,
  read : (String) -> Bytes raise,
  flavor~ : Flavor = Base,
  parse~ : ((Bytes) -> Element raise)? = None,
) -> JUnitXml raise {
  let bytes = read(path)
  let element = match parse {
    Some(parse) => parse(bytes)
    None => Element::from_bytes(bytes)
  }
  let result = JUnitXml::from_root(element, flavor~)
  result.filepath_ = Some(path)
  result
}

///|
/// Full parser injection: the callback owns reading and parsing the source.
pub fn JUnitXml::from_file_with(
  path : String,
  parse : (String) -> Element raise,
  flavor~ : Flavor = Base,
) -> JUnitXml raise {
  let result = JUnitXml::from_root(parse(path), flavor~)
  result.filepath_ = Some(path)
  result
}

///|
pub fn JUnitXml::from_reader(
  read : () -> Bytes raise,
  flavor~ : Flavor = Base,
  parse~ : ((Bytes) -> Element raise)? = None,
) -> JUnitXml raise {
  let bytes = read()
  let element = match parse {
    Some(parse) => parse(bytes)
    None => Element::from_bytes(bytes)
  }
  JUnitXml::from_root(element, flavor~)
}

///|
fn pretty_text(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn pretty_node(
  node : Element,
  out : StringBuilder,
  inherited : Map[String, String],
  counter : @ref.Ref[Int32],
  indent : String,
  depth : Int32,
  root_scope : Array[(String, String)]?,
) -> Unit raise JUnitError {
  if depth >= 128 && node.is_element() {
    raise LimitExceeded("XML nesting exceeds 128")
  }
  let state = node.state()
  match state.kind {
    Comment =>
      out.write_string("\{indent}<!--\{state.value.unwrap_or("")}-->\n")
    Instruction =>
      out.write_string(
        "\{indent}<?\{state.name} \{state.value.unwrap_or("")}?>\n",
      )
    Tag => {
      let scope = inherited.copy()
      let declarations : Array[(String, String)] = []
      for (prefix, uri) in root_scope.unwrap_or(state.namespaces) {
        declarations.push((prefix, uri))
        scope[prefix] = uri
      }
      let name = qualified(
        state.name,
        state.prefix,
        false,
        scope,
        declarations,
        counter,
      )
      let attributes = state.attributes.map(fn(attribute) {
        let (key, value) = attribute
        (
          qualified(
            key,
            state.attribute_prefixes.get(key),
            true,
            scope,
            declarations,
            counter,
          ),
          value,
        )
      })
      out.write_string("\{indent}<\{name}")
      for (prefix, uri) in declarations {
        let key = if prefix == "" { "xmlns" } else { "xmlns:\{prefix}" }
        out.write_string(" \{key}=\"\{xml_text(uri, attribute=true)}\"")
      }
      for (key, value) in attributes {
        out.write_string(" \{key}=\"\{xml_text(value, attribute=true)}\"")
      }
      if state.children_.is_empty() {
        if state.value is Some(text) && text != "" {
          out.write_string(">\{pretty_text(text)}</\{name}>\n")
        } else {
          out.write_string("/>\n")
        }
      } else {
        out.write_string(">\n")
        if state.value is Some(text) && text != "" {
          out.write_string("\{indent}\t\{pretty_text(text)}\n")
        }
        for id in state.children_ {
          let child = node.handle(id)
          pretty_node(
            child,
            out,
            scope,
            counter,
            indent + "\t",
            depth + 1,
            None,
          )
          if child.tail() is Some(text) && text != "" {
            out.write_string("\{indent}\t\{pretty_text(text)}\n")
          }
        }
        out.write_string("\{indent}</\{name}>\n")
      }
    }
  }
}

///|
/// Serialize for write(), with the UTF-8 declaration used by junitparser.
/// Pretty formatting follows minidom and may insert mixed-content whitespace.
pub fn Element::write_xml(
  self : Element,
  pretty~ : Bool = false,
) -> String raise JUnitError {
  if !pretty {
    let out = StringBuilder()
    out.write_string("<?xml version='1.0' encoding='UTF-8'?>\n")
    let state = self.state()
    for text in state.pre_doctype {
      out.write_string(text)
    }
    if state.doctype is Some((name, declaration)) &&
      name == split_name(self.tag()).1 {
      out.write_string(declaration + "\n")
    }
    if self.parent() is None {
      for text in state.prolog {
        out.write_string(text)
      }
    }
    out.write_string(self.to_xml())
    if self.parent() is None {
      for text in self.state().epilog {
        out.write_string(text)
      }
    }
    return out.to_string()
  }
  // lxml escapes CR as a character reference, which minidom rejects after
  // the root. Only literal XML space, tab and LF survive the reparse.
  if self.tail() is Some(tail) {
    for ch in tail {
      if ch != ' ' && ch != '\t' && ch != '\n' {
        raise ParseError("text follows the document element")
      }
    }
  }
  let out = StringBuilder()
  out.write_string("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
  pretty_node(
    self,
    out,
    Map([]),
    @ref.Ref(0),
    "",
    0,
    Some(self.serialization_namespaces()),
  )
  out.to_string()
}

///|
pub fn Element::write_to(
  self : Element,
  sink : (Bytes) -> Unit raise,
  pretty~ : Bool = false,
) -> Unit raise {
  sink(utf8_bytes(self.write_xml(pretty~)))
}

///|
pub fn TestSuite::write_to(
  self : TestSuite,
  sink : (Bytes) -> Unit raise,
  pretty~ : Bool = false,
) -> Unit raise {
  self.element_.write_to(sink, pretty~)
}

///|
pub fn JUnitXml::write_to(
  self : JUnitXml,
  sink : (Bytes) -> Unit raise,
  pretty~ : Bool = false,
) -> Unit raise {
  self.element_.write_to(sink, pretty~)
}

///|
pub fn TestSuite::write(
  self : TestSuite,
  write : (String, Bytes) -> Unit raise,
  path~ : String? = None,
  pretty~ : Bool = false,
) -> Unit raise {
  let destination = match path {
    Some(path) => path
    None =>
      match self.filepath_ {
        Some(path) => path
        None => raise MissingFile
      }
  }
  write(destination, utf8_bytes(self.element_.write_xml(pretty~)))
}

///|
pub fn JUnitXml::write(
  self : JUnitXml,
  write : (String, Bytes) -> Unit raise,
  path~ : String? = None,
  pretty~ : Bool = false,
) -> Unit raise {
  let destination = match path {
    Some(path) => path
    None =>
      match self.filepath_ {
        Some(path) => path
        None => raise MissingFile
      }
  }
  write(destination, utf8_bytes(self.element_.write_xml(pretty~)))
}
