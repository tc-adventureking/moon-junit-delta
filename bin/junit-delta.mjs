#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const portable = join(root, 'dist', 'junit-delta.js');
let entry = portable;
if (existsSync(join(root, 'moon.mod'))) {
  const build = spawnSync('moon', ['build', 'cmd/junit_delta', '--target', 'js', '--release', '--deny-warn'], { cwd: root, stdio: ['ignore', 'inherit', 'inherit'] });
  if (build.error || build.status !== 0) {
    process.stderr.write(`junit-delta: build failed: ${build.error?.message ?? build.status}\n`);
    process.exit(2);
  }
  entry = join(root, '_build/js/release/build/cmd/junit_delta/junit_delta.js');
}
if (!existsSync(entry)) {
  process.stderr.write('junit-delta: missing compiled entry; use a complete source checkout or portable package\n');
  process.exit(2);
}
const run = spawnSync(process.execPath, [join(root, 'bin/run.mjs'), entry, ...process.argv.slice(2)], { stdio: 'inherit' });
if (run.error) process.stderr.write(`junit-delta: ${run.error.message}\n`);
process.exitCode = run.error || run.signal ? 2 : (run.status ?? 2);
