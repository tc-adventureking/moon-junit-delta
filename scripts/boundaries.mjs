import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
const root=dirname(dirname(fileURLToPath(import.meta.url)));
const entry=process.argv[2]??join(root,'_build/js/release/build/cmd/junit_delta/junit_delta.js');
mkdirSync(join(root,'_build'),{recursive:true});
const scratch=mkdtempSync(join(root,'_build/boundaries-'));
const measure=join(scratch,'measure.json');
const env={...process.env,JUNIT_DELTA_MEASURE_PATH:measure};
const rows=[];
function run(name,args,input,expected=0) {
  const start=performance.now();
  const p=spawnSync(process.execPath,['--max-old-space-size=768',join(root,'scripts/measure.mjs'),entry,...args],{input,encoding:'utf8',timeout:120000,maxBuffer:2_000_000,env});
  assert.ifError(p.error); assert.equal(p.status,expected,`${name}: ${p.stderr} ${p.stdout.slice(0,300)}`);
  rows.push({name,wall_seconds:Number(((performance.now()-start)/1000).toFixed(3)),...JSON.parse(readFileSync(measure,'utf8'))});
  return p.stdout;
}
function request(name,value,code=0) { return JSON.parse(run(name,['jsonl'],JSON.stringify(value)+'\n',code)); }
function parse(name,xml,code=0) { return request(name,{op:'parse',document:{xml}},code); }
try {
  const empty={xml:'<testsuite/>'};
  const single={xml:'<testsuite><testcase name="x"/></testsuite>'};
  assert.equal(request('50-history',{baselines:Array(50).fill(single),candidate:single}).report.history_count,50);
  assert.equal(request('51-history',{baselines:Array(51).fill(single),candidate:single},2).ok,false);
  const shards=Array.from({length:50},(_,i)=>({xml:`<testsuite><testcase name="t${i}"/></testsuite>`}));
  assert.equal(request('50-shards',{baselines:[empty],candidate:shards,fail_on:[]}).report.candidate_count,50);
  assert.equal(request('51-shards',{baselines:[empty],candidate:[...shards,empty]},2).ok,false);
  assert.equal(parse('depth-128','<testsuite>'.repeat(127)+'<testcase name="x"/>'+'</testsuite>'.repeat(127)).report.cases.length,1);
  assert.equal(parse('depth-129','<testsuite>'.repeat(128)+'<testcase name="x"/>'+'</testsuite>'.repeat(128),2).error_code,'limit_exceeded');
  const prefix='<testsuite><!--',suffix='--></testsuite>';
  const exact=prefix+'x'.repeat(10_000_000-prefix.length-suffix.length)+suffix;
  assert.equal(parse('XML-10M-units',exact).ok,true);
  assert.equal(parse('XML-over-10M',exact+' ',2).error_code,'limit_exceeded');
  assert.equal(parse('events-2M','<testsuite>'+'<x/>'.repeat(1_999_997)+'</testsuite>').ok,true);
  assert.equal(parse('events-over-2M','<testsuite>'+'<x/>'.repeat(1_999_998)+'</testsuite>',2).error_code,'limit_exceeded');
  assert.equal(parse('attribute-preflight','<testsuite '+Array.from({length:50000},(_,i)=>`a${i}="x"`).join(' ')+'/>',2).error_code,'limit_exceeded');
  const xmlfile=join(scratch,'shared.xml');
  writeFileSync(xmlfile,'<testsuite name="'+'x'.repeat(200000)+'">'+Array.from({length:50000},(_,i)=>`<testcase name="t${i}"/>`).join('')+'</testsuite>');
  const compare=['compare','--baseline',xmlfile,'--candidate',xmlfile];
  assert.ok(run('50k-cases-200k-shared-name',[...compare,'--format','md','--limit','0']).includes('candidate: 50000'));
  const tooLarge=spawnSync(process.execPath,[join(root,'bin/run.mjs'),entry,...compare,'--format','json'],{encoding:'utf8',timeout:30000,maxBuffer:1_000_000});
  assert.ifError(tooLarge.error); assert.equal(tooLarge.status,2); assert.match(tooLarge.stderr,/output_limit/); assert.equal(tooLarge.stdout,'');
  const bytefile=join(scratch,'bytes.xml'), basefile=join(scratch,'empty.xml');
  writeFileSync(basefile,empty.xml);
  const payload=20_000_000-prefix.length-suffix.length;
  writeFileSync(bytefile,prefix+'中'.repeat(Math.floor(payload/3))+'x'.repeat(payload%3)+suffix);
  assert.equal(readFileSync(bytefile).length,20_000_000);
  const bytesArgs=['compare','--baseline',basefile,'--candidate',bytefile,'--fail-on','none'];
  run('file-20M-bytes',bytesArgs);
  writeFileSync(bytefile,' ',{flag:'a'});
  run('file-over-20M-bytes',bytesArgs,undefined,2);
  // Delayed producer: test the real pipe, not an immediately available stdin buffer.
  await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[join(root,'bin/run.mjs'),entry,'compare','--baseline',basefile,'--candidate','-','--fail-on','none'],{stdio:['pipe','pipe','pipe']});
    let out='',err='';
    child.stdout.on('data',b=>out+=b); child.stderr.on('data',b=>err+=b); child.on('error',reject); child.stdin.on('error',reject);
    child.on('close',code=>{ try {assert.equal(code,0,err);assert.match(out,/candidate 1/);resolve();} catch(e){reject(e);} });
    setTimeout(()=>{child.stdin.write('<testsuite>');setTimeout(()=>child.stdin.end('<testcase name="x"/></testsuite>'),100);},100);
  });
  // Drain instead of retaining up to 100 MB; verify complete JSON lines at the boundary.
  await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,['--max-old-space-size=768',join(root,'scripts/measure.mjs'),entry,'jsonl'],{env,stdio:['pipe','pipe','pipe']});
    let units=0,lines=0,tail='',last='',err='';
    const timer=setTimeout(()=>{child.kill();reject(Error('JSONL budget test timed out'));},120000);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data',chunk=>{units+=chunk.length;const parts=(tail+chunk).split('\n');tail=parts.pop();if(parts.length){lines+=parts.length;last=parts.at(-1);}});
    child.stderr.on('data',b=>err+=b);child.on('error',reject);child.stdin.on('error',reject);
    child.on('close',code=>{clearTimeout(timer);try{assert.equal(code,2,err);assert.equal(tail,'');assert.ok(units<=100_000_000);assert.ok(lines<1_000_000);const final=JSON.parse(last);assert.equal(final.error_code,'output_limit');assert.equal(final.line,lines);rows.push({name:'JSONL-aggregate-output',output_units:units,complete_lines:lines,...JSON.parse(readFileSync(measure,'utf8'))});resolve();}catch(e){reject(e);}});
    child.stdin.end('{\n'.repeat(1_000_000));
  });
  const summary={status:'passed',checks:rows,delayed_stdin_pipe:'passed',oversized_JSON:'rejected_before_serialization'};
  writeFileSync(join(root,'_build/boundaries.json'),JSON.stringify(summary,null,2)+'\n');
  console.log(JSON.stringify(summary,null,2));
} finally {
  assert.equal(dirname(resolve(scratch)),resolve(root,'_build'));
  rmSync(scratch,{recursive:true,force:true});
}
