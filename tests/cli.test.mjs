import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { linkSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const launcher = fileURLToPath(new URL('../bin/junit-delta.mjs', import.meta.url));

function workspace(t) {
  const dir = mkdtempSync(join(tmpdir(), 'junit-delta-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function run(dir, args, input) {
  const result = spawnSync(process.execPath, [launcher, ...args], {
    cwd: dir, encoding: 'utf8', input,
  });
  if (result.error) throw result.error;
  assert.equal(result.signal, null);
  return result;
}

test('a real Node JUnit report keeps its failing top-level test', t => {
  const dir = workspace(t);
  writeFileSync(join(dir, 'sample.mjs'), "import test from 'node:test';\ntest('top failure', () => { throw Error('expected failure'); });\n");
  const producer = spawnSync(process.execPath, ['--test', '--test-reporter=junit', 'sample.mjs'], {
    cwd: dir, encoding: 'utf8', env: { ...process.env, NODE_TEST_CONTEXT: undefined },
  });
  assert.equal(producer.status, 1, producer.stderr);
  assert.match(producer.stdout, /<testsuites>\s*<testcase/);
  const merged = run(dir, ['merge', '--glob', '-', '-'], producer.stdout);
  assert.equal(merged.status, 0, merged.stderr);
  assert.match(merged.stdout, /tests="1"/);
  assert.match(merged.stdout, /failures="1"/);
  assert.match(merged.stdout, /<failure\b/);
  for (const report of [producer.stdout, merged.stdout]) {
    const verified = run(dir, ['verify', '--glob', '-'], report);
    assert.equal(verified.status, 1);
    assert.match(verified.stderr, /top failure/);
  }
});

test('rerunning merge ignores its output and hard-link aliases', t => {
  const dir = workspace(t);
  const file = name => join(dir, name);
  writeFileSync(file('shard.xml'), '<testsuite><testcase name="only"/></testsuite>');
  const merge = () => run(dir, ['merge', '--glob', '*.xml', './out.xml']);
  const first = merge();
  assert.equal(first.status, 0, first.stderr);
  const expected = readFileSync(file('out.xml'), 'utf8');
  assert.match(expected, /tests="1"/);
  assert.match(expected, /<testsuites\b[^>]*>\s*<testsuite\b[^>]*>\s*<testcase\b[^>]*name="only"/);
  linkSync(file('out.xml'), file('alias.xml'));
  for (let n = 0; n < 2; n++) {
    const next = merge();
    assert.equal(next.status, 0, next.stderr);
    assert.equal(readFileSync(file('out.xml'), 'utf8'), expected);
  }
  for (const pattern of ['absent*.xml', 'alias.xml']) {
    const failed = run(dir, ['merge', '--glob', pattern, 'out.xml']);
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, /no input reports matched/);
    assert.equal(readFileSync(file('out.xml'), 'utf8'), expected);
  }
});

test('merging nested shards keeps classless testcase identities and counts', t => {
  const dir = workspace(t);
  const left = '<testsuite name="run"><testsuite name="web"><testcase name="login"/></testsuite></testsuite>';
  const right = '<testsuite name="run"><testsuite name="api"><testcase name="login"><failure/></testcase></testsuite></testsuite>';
  writeFileSync(join(dir, 'web.xml'), left);
  writeFileSync(join(dir, 'api.xml'), right);
  const merged = run(dir, ['merge', 'web.xml', 'api.xml', 'merged.xml']);
  assert.equal(merged.status, 0, merged.stderr);
  const xml = readFileSync(join(dir, 'merged.xml'), 'utf8');
  assert.match(xml, /<testsuites\b[^>]*tests="2"/);
  assert.match(xml, /<testsuites\b[^>]*failures="1"/);
  assert.equal((xml.match(/<testcase\b/g) || []).length, 2);
  assert.match(xml, /<testsuite\b[^>]*name="api"[^>]*>\s*<testcase\b[^>]*name="login"/);
  const comparison = run(dir, ['compare', '--baseline', 'merged.xml', '--candidate', 'web.xml', '--candidate', 'api.xml', '--format', 'json']);
  assert.equal(comparison.status, 0, comparison.stderr || comparison.stdout);
  const checked = run(dir, ['verify', 'merged.xml']);
  assert.equal(checked.status, 1);
  assert.match(checked.stderr, /failed testcase login/);
  writeFileSync(join(dir, 'invalid.xml'), '<testsuite name="run"><testsuites><testsuite><testcase/></testsuite></testsuites></testsuite>');
  const invalid = run(dir, ['merge', 'web.xml', 'invalid.xml', 'merged.xml']);
  assert.equal(invalid.status, 1, invalid.stderr);
  assert.match(invalid.stderr, /nested testsuites/);
  assert.equal(readFileSync(join(dir, 'merged.xml'), 'utf8'), xml);
});

test('globbed dash filename and empty files do not turn into a passing check', t => {
  const dir = workspace(t);
  writeFileSync(join(dir, '-'), '<testsuite><testcase name="dash"><error/></testcase></testsuite>');
  const dash = run(dir, ['verify', '--glob', '*'], '<testsuite><testcase name="stdin"/></testsuite>');
  assert.equal(dash.status, 1);
  assert.match(dash.stderr, /failed testcase dash/);
  for (const [args, message] of [
    [['--glob', '*.xml'], /no input reports matched/],
    [['-'], /no testcases/],
  ]) {
    const failed = run(dir, ['verify', ...args], '<testsuites/>');
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, message);
  }
});
