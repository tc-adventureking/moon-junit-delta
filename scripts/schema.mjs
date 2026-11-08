import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';

const root=dirname(dirname(fileURLToPath(import.meta.url)));
const schema=JSON.parse(readFileSync(join(root,'schemas/report.schema.json'),'utf8'));
const ajv=new Ajv2020({strict:true,allErrors:true});
assert.equal(ajv.validateSchema(schema),true,JSON.stringify(ajv.errors));
const validate=ajv.compile(schema);
let checked=0;
function walk(directory) {
  for(const item of readdirSync(directory,{withFileTypes:true})) {
    const path=join(directory,item.name);
    if(item.isDirectory()) walk(path);
    else if(item.name.endsWith('.json')) {
      const value=JSON.parse(readFileSync(path,'utf8'));
      const report=value.report??value;
      if(report.schema_version===1) {
        assert.equal(validate(report),true,`${path}: ${JSON.stringify(validate.errors)}`); checked++;
      }
    }
  }
}
walk(join(root,'examples'));
assert.ok(checked>0);
const sample=JSON.parse(readFileSync(join(root,'examples/expected.json'),'utf8'));
const mutations=[
  d=>d.entries[0].after.time_us='10000',
  d=>d.entries[0].after.time_us=-1,
  d=>d.entries[0].after.attempts=0,
  d=>d.entries[0].id=['class','x'],
  d=>d.gate.passed=true,
  d=>d.gate.violations.push(d.gate.violations[0]),
  d=>d.counts.typo=1,
  d=>d.schema_version=2,
];
for(const change of mutations) { const altered=structuredClone(sample); change(altered); assert.equal(validate(altered),false); }
console.log(`JSON Schema: ${checked} golden reports accepted; ${mutations.length} invalid report mutations rejected.`);
