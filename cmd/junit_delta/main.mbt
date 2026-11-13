///|
extern "js" fn argv() -> String =
  #| () => JSON.stringify(process.argv.slice(2))

///|
extern "js" fn read_file(path : String, report : Bool) -> String =
  #| (path, report) => globalThis.__junitDeltaRead(path, report)

///|
extern "js" fn write_file(path : String, text : String) -> String =
  #| (path, text) => globalThis.__junitDeltaWrite(path, text)

///|
extern "js" fn glob_files(pattern : String) -> String =
  #| (pattern) => globalThis.__junitDeltaGlob(pattern)

///|
extern "js" fn write_result(
  stdout : String,
  stderr : String,
  status : Int32,
) -> Unit =
  #| (out, err, status) => { process.stdout.write(out); process.stderr.write(err); process.exitCode = status; }

///|
fn main raise {
  let args = match @json.parse(argv()) {
    Array(items) =>
      items.map(item => {
        match item {
          String(s) => s
          _ => ""
        }
      })
    _ => []
  }
  let report = !args.is_empty() && (args[0] == "merge" || args[0] == "verify")
  let result = @delta.run_cli(
    args,
    path => {
      let value = @json.parse(read_file(path, report))
      match value {
        { "ok": true, "text": String(s), .. } => s
        { "error": String(e), .. } => raise @delta.InvalidInput(e)
        _ => raise @delta.InvalidInput("invalid host response")
      }
    },
    write=Some((path, text) => {
      match @json.parse(write_file(path, text)) {
        { "ok": true, .. } => ()
        { "error": String(error), .. } => raise @delta.InvalidInput(error)
        _ => raise @delta.InvalidInput("invalid host write response")
      }
    }),
    glob=Some(pattern => {
      match @json.parse(glob_files(pattern)) {
        Array(paths) =>
          paths.map(path => {
            match path {
              String(path) => path
              _ => ""
            }
          })
        _ => raise @delta.InvalidInput("invalid host glob response")
      }
    }),
  )
  write_result(result.stdout, result.stderr, result.status)
}
