import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const entry = process.argv[2] ?? join(root, '_build/js/release/build/cmd/junit_delta/junit_delta.js');
const {reference,vectors} = JSON.parse(readFileSync(join(root,'fixtures/junitparser-contract.json'),'utf8'));
let matched=0, rejected=0;
for(let i=0;i<vectors.length;i+=50) {
  const batch=vectors.slice(i,i+50);
  const input=batch.map(v=>JSON.stringify({op:'parse',document:{xml:v.xml}})).join('\n')+'\n';
  const p=spawnSync(process.execPath,[join(root,'bin/run.mjs'),entry,'jsonl'],{input,encoding:'utf8',timeout:30000,maxBuffer:8_000_000});
  assert.ifError(p.error); assert.ok(p.status===0||p.status===2,p.stderr);
  const results=p.stdout.trim().split('\n').map(JSON.parse);
  assert.equal(results.length,batch.length);
  for(let j=0;j<batch.length;j++) {
    const v=batch[j], r=results[j];
    if(v.rejection) {
      assert.equal(r.ok,false,v.name); assert.equal(r.error_code,v.rejection,v.name); rejected++;
    } else {
      assert.equal(v.upstream_accepts,true,v.name); assert.equal(r.ok,true,`${v.name}: ${r.error}`);
      const got=r.report.cases.map(c=>Object.fromEntries(reference.projection.map(k=>[k,k==='interim_count'?c.interim_results.length:c[k]])));
      assert.deepEqual(got,v.expected,v.name); matched++;
    }
  }
}
console.log(`${reference.reference} saved oracle: ${matched} matches, ${rejected} documented rejections, 0 mismatches`);
