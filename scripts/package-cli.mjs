import { readVersion } from './version.mjs';
// Run after `moon build cmd/junit_delta --target js --release --deny-warn`.
import { cpSync, copyFileSync, mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';

const root=dirname(dirname(fileURLToPath(import.meta.url)));
const version=readVersion(root);
const entry=process.argv[2]??join(root,'_build/js/release/build/cmd/junit_delta/junit_delta.js');
const output=resolve(root,`_build/release/junit-delta-${version}-cli`);
assert.equal(dirname(output),resolve(root,'_build/release'));
if(existsSync(output)) rmSync(output,{recursive:true});
mkdirSync(join(output,'dist'),{recursive:true});
copyFileSync(entry,join(output,'dist/junit-delta.js'));
for(const file of ['README.md','LICENSE']) copyFileSync(join(root,file),join(output,file));
for(const dir of ['bin','docs','third_party','fixtures','schemas']) cpSync(join(root,dir),join(output,dir),{recursive:true});
mkdirSync(join(output,'examples'),{recursive:true});
for(const file of readdirSync(join(root,'examples'))) {
  if(/\.(xml|json|md)$/.test(file)) copyFileSync(join(root,'examples',file),join(output,'examples',file));
}
cpSync(join(root,'examples/scenarios'),join(output,'examples/scenarios'),{recursive:true});
assert.equal(existsSync(join(output,'moon.mod')),false);
const p=spawnSync(process.execPath,[join(output,'bin/junit-delta.mjs'),'compare','--baseline','examples/baseline.xml','--candidate','examples/candidate.xml','--format','json'],{cwd:output,encoding:'utf8',timeout:30000});
assert.ifError(p.error); assert.equal(p.status,1,p.stderr);
assert.equal(p.stdout,readFileSync(join(root,'examples/expected.json'),'utf8'));
const files=[];
function walk(dir) {
  for(const ent of readdirSync(dir,{withFileTypes:true})) {
    const path=join(dir,ent.name);
    if(ent.isDirectory()) walk(path);
    else if(ent.name!=='MANIFEST.json') files.push({path:relative(output,path).replaceAll('\\','/'),sha256:createHash('sha256').update(readFileSync(path)).digest('hex')});
  }
}
walk(output); files.sort((a,b)=>a.path.localeCompare(b.path,'en'));
writeFileSync(join(output,'MANIFEST.json'),JSON.stringify({name:'junit-delta',version,runtime:'Node.js 24',files},null,2)+'\n');
console.log(`Portable CLI verified: ${output} (${files.length} files)`);
