"""Reproduce the pinned mature-library read contract without installing it.

No upstream implementation is copied. Python is a development-only dependency.
"""
import argparse
import hashlib
import json
import random
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--wheel', type=Path, required=True)
parser.add_argument('--entry', type=Path, default=root/'_build/js/release/build/cmd/junit_delta/junit_delta.js')
parser.add_argument('--write-oracle', action='store_true', help='Explicitly refresh the saved upstream oracle after review')
parser.add_argument('--oracle-output', type=Path, help='Write regenerated oracle elsewhere for byte-for-byte verification')
args = parser.parse_args()
wheel = args.wheel.resolve()
output = root/'_build/reference'
output.mkdir(parents=True, exist_ok=True)
wheel_hash = hashlib.sha256(wheel.read_bytes()).hexdigest()
assert wheel_hash == '553535b8cd1672a9c8bd2c7326ae1ae69279267fbc562106b5aa44d3c5f769af'
sys.path.insert(0, str(wheel))
from junitparser import xunit2

runner = ['node', str(root/'bin/run.mjs'), str(args.entry), 'jsonl']
fields = ('name','classname','is_passed','is_failure','is_error','is_skipped','is_flaky','is_rerun','interim_count')
def reference(xml):
    # The contract is UTF-8 input; bytes work with both upstream XML backends.
    doc = xunit2.JUnitXml.fromstring(xml.encode('utf-8'))
    records=[]
    for suite in doc:
        for case in suite:
            records.append({k: (len(case.interim_result) if k=='interim_count' else getattr(case,k)) for k in fields})
    return records

vectors=[]
def add(name,xml,rejection=None):
    try:
        expected=reference(xml)
        accepted=True
    except Exception:
        expected=None; accepted=False
    vectors.append({'name':name,'xml':xml,'upstream_accepts':accepted,'expected':expected,'rejection':rejection})

def case(name,body='',class_='C',time=None):
    attrs=' name='+quoteattr(name)
    if class_ is not None: attrs+=' classname='+quoteattr(class_)
    if time is not None: attrs+=' time='+quoteattr(time)
    return '<testcase'+attrs+'>'+body+'</testcase>'
def suite(body): return '<testsuite name="S">'+body+'</testsuite>'

states=['','<failure/>','<error/>','<skipped/>','<flakyFailure/>']
for i,a in enumerate(states+['<failure/><error/>','<failure/><rerunError/>']):
    for j,b in enumerate(states):
        add(f'states-{i}-{j}',suite(case('before',a)+case('after',b)))
for body in ['<failure/><error/><skipped/>','<failure/><flakyError/>','<error/><flakyFailure/><rerunError/>','<flakyError/><flakyFailure/>','<error/><rerunFailure/><rerunError/>']:
    add('flags-'+str(len(vectors)),suite(case('x',body)))
add('nested-order','<testsuites><testsuite name="a"><testsuite name="b">'+case('child')+'</testsuite>'+case('parent')+'<testsuite name="c">'+case('child2')+'</testsuite>'+case('parent2')+'</testsuite><testsuite>'+case('last')+'</testsuite></testsuites>')
add('duplicates',suite(case('x','<failure/>')+case('x')+case('x','<error/>')))
add('missing-versus-empty-class',suite(case('x',class_=None)+case('x',class_='')))
add('decoded-whitespace',"<testsuite><testcase name=' a\t b\n c&#10; &#x1F600; &amp;' classname=' &#9; C '/></testsuite>")
add('xml-features',"<?xml version='1.0' encoding='UTF-8'?><testsuite><!--c--><testcase name='x'><failure message='&lt;x&gt;'><![CDATA[<x>]]></failure><system-out>ok</system-out></testcase></testsuite>")
add('empty','<testsuites/>')
for path in sorted((root/'fixtures').glob('*.xml')):
    add('fixture-'+path.name,path.read_text(encoding='utf-8'))

rejects=[
    ('missing_name',suite('<testcase/>')),('missing_name',suite(case(''))),
    ('retry_conflict',suite(case('x','<rerunFailure/>'))),
    ('retry_conflict',suite(case('x','<skipped/><flakyError/>'))),
    ('invalid_structure',suite('<extra>'+case('x')+'</extra>')),
    ('invalid_structure',suite(case('x','<extra><failure/></extra>'))),
    ('invalid_structure','<testsuites><testsuites/></testsuites>'),
    ('unsupported_namespace','<testsuite xmlns="urn:junit">'+case('x')+'</testsuite>'),
    ('doctype','<!DOCTYPE testsuite><testsuite/>'),
    ('unsupported_encoding',"<?xml version='1.0' encoding='ISO-8859-1'?><testsuite/>"),
    ('malformed_xml','<testsuite>'),('malformed_xml','<testsuite/><testsuite/>'),
    ('malformed_xml',"<testsuite><testcase name='a' name='b'/></testsuite>"),
]
for invalid in ['-1','1e3','nan','inf','.1','1.',' 1','1,0','9000001']:
    rejects.append(('invalid_time',suite(case('x',time=invalid))))
for code,xml in rejects: add('reject-'+code+'-'+str(len(vectors)),xml,code)

rng=random.Random(20261109)
names=['a',' Z ','参数 & < >','emoji😀','line\nname','x|`*[link]','a:b','aa','z']
valid_tags=states+['<failure/><error/>','<error/><skipped/>','<failure/><rerunError/>','<flakyError/><flakyFailure/>','<error/><flakyFailure/>']
for i in range(1000):
    children=[]
    for j in range(rng.randrange(0,9)):
        xml=case(rng.choice(names),rng.choice(valid_tags),rng.choice([None,'','C',' C ','类😀']),rng.choice([None,'','0','0.0000009','1.9999999','123.5','9000000']))
        if rng.random()<0.3: xml='<testsuite name="nested">'+xml+'</testsuite>'
        children.append(xml)
    add('generated-'+str(i),suite(''.join(children)))

mismatches=[]
accepted=0; rejected=0
for start in range(0,len(vectors),50):
    batch=vectors[start:start+50]
    requests=''.join(json.dumps({'op':'parse','document':{'xml':v['xml']}},ensure_ascii=True)+'\n' for v in batch)
    process=subprocess.run(runner,input=requests,text=True,encoding='utf-8',capture_output=True,timeout=60)
    assert process.returncode in [0,2],(process.returncode,process.stderr)
    rows=[json.loads(line) for line in process.stdout.splitlines()]
    assert len(rows)==len(batch),(len(rows),len(batch),process.stderr)
    for v,actual in zip(batch,rows):
        if v['rejection']:
            rejected+=1
            if actual.get('ok') or actual.get('error_code')!=v['rejection']: mismatches.append((v,actual))
        elif not v['upstream_accepts']:
            mismatches.append((v,actual))
        elif not actual.get('ok'):
            mismatches.append((v,actual))
        else:
            accepted+=1
            got=[{k:(len(c['interim_results']) if k=='interim_count' else c[k]) for k in fields} for c in actual['report']['cases']]
            if got!=v['expected']: mismatches.append((v,got))

result={'reference':'junitparser 5.0.3','wheel_sha256':wheel_hash,'seed':20261109,'documents':len(vectors),'matching_accepted':accepted,'documented_rejections':rejected,'mismatches':len(mismatches),'projection':list(fields)}
(output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8',newline='\n')
if mismatches:
    (output/'mismatches.json').write_text(json.dumps(mismatches,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result)); print(json.dumps(mismatches[:2],ensure_ascii=True)); sys.exit(1)
# The dynamic corpus is always regenerated. Only explicit maintainer opt-in rewrites the saved oracle.
public=vectors[:len(vectors)-1000]+vectors[-128:]
if args.write_oracle or args.oracle_output:
    destination=args.oracle_output or root/'fixtures/junitparser-contract.json'
    destination.write_text(json.dumps({'reference':result,'vectors':public},ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps(result))
