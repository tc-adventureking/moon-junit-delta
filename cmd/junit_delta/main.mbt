///|
extern "js" fn argv() -> String =
  #| () => JSON.stringify(process.argv.slice(2))

///|
extern "js" fn read_file(path : String) -> String =
  #| (path) => globalThis.__junitDeltaRead(path)

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
  let result = @delta.run_cli(args, path => {
    let value = @json.parse(read_file(path))
    match value {
      { "ok": true, "text": String(s), .. } => s
      { "error": String(e), .. } => raise @delta.InvalidInput(e)
      _ => raise @delta.InvalidInput("invalid host response")
    }
  })
  write_result(result.stdout, result.stderr, result.status)
}
