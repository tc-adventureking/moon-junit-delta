import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const source = dirname(dirname(fileURLToPath(import.meta.url)));
const portable = process.argv[2] === '--portable';
const root = portable ? resolve(process.argv[3]) : source;
if (portable) assert.equal(existsSync(join(root, 'moon.mod')), false);
const command = portable ? [join(root, 'bin/junit-delta.mjs')] : [join(root, 'bin/run.mjs'), join(root, '_build/js/release/build/cmd/junit_delta/junit_delta.js')];
let checked = 0;
for (const name of ['pr', 'retry', 'shards']) {
  const directory = join(root, 'examples/scenarios', name);
  const manifest = JSON.parse(readFileSync(join(directory, 'scenario.json'), 'utf8'));
  for (const check of manifest.checks) {
    const p = spawnSync(process.execPath, [...command, ...check.args], { cwd: root, encoding: 'utf8', timeout: 30000 });
    assert.ifError(p.error); assert.equal(p.signal, null);
    assert.equal(p.status, check.exit_code, p.stderr);
    if (check.stderr_contains) {
      assert.equal(p.stdout, ''); assert.ok(p.stderr.includes(check.stderr_contains));
    } else {
      if (check.expected) assert.equal(p.stdout, readFileSync(join(directory, check.expected), 'utf8'));
      const report = JSON.parse(p.stdout);
      assert.deepEqual(report.counts, check.counts);
      assert.deepEqual(report.gate.violations, check.violations);
      if (name === 'retry') {
        const transport = report.entries.find(e => e.id[2] === 'transport');
        const cache = report.entries.find(e => e.id[2] === 'cache');
        assert.equal(transport.known_flaky, true);
        assert.equal(transport.after.outcome, 'failed');
        assert.equal(cache.after.outcome, 'passed'); assert.equal(cache.after.flaky, true);
        assert.ok(report.entries.every(e => e.after.attempts === 2));
      }
    }
    checked++;
  }
}
console.log(`Three complete scenarios: ${checked} command checks passed (${portable ? 'portable' : 'source build'}).`);
