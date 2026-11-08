import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const source = dirname(dirname(fileURLToPath(import.meta.url)));
const portable = process.argv[2] === '--portable';
const root = portable ? resolve(process.argv[3]) : source;
if (portable) assert.equal(existsSync(join(root, 'moon.mod')), false);
const entry = process.argv[2] ?? join(root, '_build/js/release/build/cmd/junit_delta/junit_delta.js');
const runtime = join(root, 'bin/run.mjs');
const command = portable ? [join(root, 'bin/junit-delta.mjs')] : [runtime, entry];
const args = ['compare', '--baseline', 'examples/baseline.xml', '--candidate', 'examples/candidate.xml'];
let checks = 0;
function run(extra, input) {
  const r = spawnSync(process.execPath, [...command, ...extra], { cwd: root, input, encoding: 'utf8', timeout: 30000 });
  assert.ifError(r.error); assert.equal(r.signal, null); checks++;
  return r;
}
const first = run([...args, '--format', 'json']);
assert.equal(first.status, 1);
const report = JSON.parse(first.stdout);
assert.deepEqual(report.counts, { added_failing: 1, fixed: 1, new_failure: 1, removed: 1, unchanged: 2 });
assert.equal(report.entries.filter(e => e.slowdown).length, 1);
assert.equal(report.entries.filter(e => e.after?.flaky).length, 1);
assert.equal(run([...args,'--format','json']).stdout, first.stdout);
assert.equal(first.stdout, readFileSync(join(root,'examples/expected.json'),'utf8'));
assert.equal(run([...args,'--format','md']).stdout, readFileSync(join(root,'examples/expected.md'),'utf8'));
assert.equal(run([...args,'--fail-on','none']).status, 0);
assert.equal(run([...args,'--fail-on','slowdown,flaky']).status, 1);
const hist = JSON.parse(run(['compare','--baseline','examples/history.xml',...args.slice(1),'--format','json']).stdout);
assert.equal(hist.entries.find(e=>e.category==='new_failure').known_flaky, true);
assert.equal(hist.gate.exit_code, 1);
assert.equal(hist.entries.find(e=>e.slowdown).baseline_time_us, 400000);
assert.equal(run(['--help']).status, 0);
assert.equal(run(['--version']).stdout, 'junit-delta 0.1.0\n');
const missing=run(['compare','--baseline','missing-does-not-exist.xml','--candidate','examples/candidate.xml']);
assert.equal(missing.status,2); assert.equal(missing.stdout,'');
for (const extra of [['--format','wrong'],['--duplicates','wrong'],['--fail-on','typo'],['--slowdown-pct','1000001'],['--limit','oops']]) {
  assert.equal(run([...args,...extra]).status,2);
}
mkdirSync(join(root,'_build'), { recursive: true });
const temporary = mkdtempSync(join(root,'_build','e2e-'));
try {
  const input=join(temporary,'input.xml');
  writeFileSync(input,Buffer.from([0xff,0xfe,0x41,0x00]));
  assert.equal(run(['compare','--baseline','examples/baseline.xml','--candidate',input]).status,2);
  writeFileSync(input,Buffer.from([0xc3,0x28]));
  assert.equal(run(['compare','--baseline','examples/baseline.xml','--candidate',input]).status,2);
  writeFileSync(input,'<testsuite><testcase name="x"/></testsuite>');
  assert.equal(run(['compare','--baseline',input,'--candidate',input,'--candidate',input]).status,2);
  assert.equal(run(['compare','--baseline',input,'--candidate',input,'--candidate',input,'--duplicates','attempts']).status,0);
  writeFileSync(input,'<testsuite>');
  assert.equal(run(['compare','--baseline','examples/baseline.xml','--candidate',input]).status,2);
  const stdin = Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),readFileSync(join(root,'examples/candidate.xml'))]);
  assert.equal(run(['compare','--baseline','examples/baseline.xml','--candidate','-'],stdin).status,1);
  assert.equal(run(['compare','--baseline','-','--candidate','-'],stdin).status,2);
  const good={baselines:[{xml:'<testsuite/>'}],candidate:{xml:'<testsuite><testcase name="x"/></testsuite>'}};
  const lines=run(['jsonl'],JSON.stringify(good)+'\n{\n');
  assert.equal(lines.status,2);
  const outputs=lines.stdout.trim().split('\n').map(JSON.parse);
  assert.equal(outputs[0].ok,true); assert.equal(outputs[1].ok,false);
  const dupKeys=run(['jsonl'],'{"baselines":[],"baselines":[],"candidate":{}}\n');
  assert.equal(dupKeys.status,2);
  const sharded={baselines:[[{xml:'<testsuite><testcase name="x"/></testsuite>'},{xml:'<testsuite><testcase name="y"/></testsuite>'}]],candidate:[{xml:'<testsuite><testcase name="x"/></testsuite>'},{xml:'<testsuite><testcase name="y"/></testsuite>'}]};
  assert.equal(run(['jsonl'],JSON.stringify(sharded)).status,0);
} finally {
  assert.equal(dirname(resolve(temporary)), resolve(root,'_build'));
  rmSync(temporary, {recursive:true,force:true});
}
console.log(`CLI end-to-end checks passed: ${checks}`);
