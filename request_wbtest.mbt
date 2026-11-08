///|
test "unknown request fields fail closed with an exact JSON path" {
  let cases = [
    ("{\"fail_onn\":[]}", "$[\"fail_onn\"]"),
    (
      "{\"op\":\"parse\",\"document\":{\"xml\":\"<testsuite/>\",\"sorce\":\"x\"}}",
      "$[\"document\"][\"sorce\"]",
    ),
    (
      "{\"baselines\":[{\"xml\":\"<testsuite/>\",\"extra\":0}],\"candidate\":{}}",
      "$[\"baselines\"][0][\"extra\"]",
    ),
    (
      "{\"baselines\":[[{\"xml\":\"<testsuite/>\",\"extra\":0}]],\"candidate\":{}}",
      "$[\"baselines\"][0][0][\"extra\"]",
    ),
    (
      "{\"baselines\":[{\"xml\":\"<testsuite/>\"}],\"candidate\":[{\"xml\":\"<testsuite/>\",\"extra\":0}]}",
      "$[\"candidate\"][0][\"extra\"]",
    ),
    ("{\"op\":\"parse\",\"document\":{},\"fail_on\":[]}", "$[\"fail_on\"]"),
  ]
  for (request, expected_path) in cases {
    match evaluate_request(request) {
      {
        "ok": false,
        "exit_code": 2,
        "error_code": "unknown_field",
        "error_path": String(path),
        ..
      } => assert_eq(path, expected_path)
      _ => assert_true(false, msg=request)
    }
  }
}

///|
test "unknown key path quotes controls and preserves literal key" {
  let result = evaluate_request("{\"quote\\\".\\n\":1}")
  match result {
    { "error_path": String(path), .. } =>
      assert_eq(path, "$[\"quote\\\".\\n\"]")
    _ => assert_true(false)
  }
}
