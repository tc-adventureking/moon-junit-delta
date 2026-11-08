import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cpus, platform, arch } from 'node:os';
const root=dirname(dirname(fileURLToPath(import.meta.url)));
const entry=process.argv[2]??join(root,'_build/js/release/build/cmd/junit_delta/junit_delta.js');
const n=20000;
const cases=Array.from({length:n},(_,i)=>`<testcase classname="scale" name="test${String(i).padStart(5,'0')}" time="0.001"/>`);
const base='<testsuite>'+cases.join('')+'</testsuite>';
cases[n/2]=`<testcase classname="scale" name="test${String(n/2).padStart(5,'0')}" time="0.001"><failure/></testcase>`;
const input=JSON.stringify({baselines:[{xml:base}],candidate:{xml:'<testsuite>'+cases.join('')+'</testsuite>'}})+'\n';
const times=[], hashes=[];
for(let i=0;i<3;i++) {
  const start=performance.now();
  const p=spawnSync(process.execPath,[join(root,'bin/run.mjs'),entry,'jsonl'],{input,encoding:'utf8',maxBuffer:32_000_000,timeout:120000});
  assert.ifError(p.error); assert.equal(p.status,1,p.stderr);
  times.push(Number(((performance.now()-start)/1000).toFixed(3)));
  const result=JSON.parse(p.stdout).report;
  assert.deepEqual(result.counts,{new_failure:1,unchanged:n-1});
  assert.equal(result.candidate_count,n);
  hashes.push(createHash('sha256').update(p.stdout).digest('hex'));
}
assert.equal(new Set(hashes).size,1);
console.log(JSON.stringify({testcases_per_report:n,runs:3,wall_seconds_including_startup_io_json:times,sha256:hashes[0],platform:platform(),arch:arch(),cpu:cpus()[0]?.model,node:process.version},null,2));
