"""Deterministic independent comparison oracle and malformed-XML checks (stdlib only)."""
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SEED = 20261109


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--entry', type=Path, default=ROOT/'_build/js/release/build/cmd/junit_delta/junit_delta.js')
    args = parser.parse_args()
    rng = random.Random(SEED)
    jobs = []

    def xml(cases):
        suite = ET.Element('testsuite', name='generated')
        for name, (state, time, flaky) in cases.items():
            case = ET.SubElement(suite, 'testcase', classname='C"[😀]', name=name, time=f'{time/1_000_000:.6f}')
            if state != 'passed': ET.SubElement(case, {'failed':'failure', 'errored':'error', 'skipped':'skipped'}[state])
            if flaky: ET.SubElement(case, 'flakyFailure')
        return ET.tostring(suite, encoding='unicode')

    def category(before, after):
        if after is None: return 'removed'
        if before is None: return 'added_failing' if after in ('failed', 'errored') else 'added'
        if after in ('failed', 'errored'): return 'still_failing' if before in ('failed', 'errored') else 'new_failure'
        if after == 'skipped': return 'unchanged' if before == 'skipped' else 'newly_skipped'
        if before in ('failed', 'errored'): return 'fixed'
        return 'unskipped' if before == 'skipped' else 'unchanged'

    names = [f'case{i}["\\|😀中文]' for i in range(12)]
    for _ in range(500):
        runs = []
        for _ in range(4):
            run = {}
            for name in rng.sample(names, rng.randint(0, len(names))):
                state = rng.choice(['passed', 'failed', 'errored', 'skipped'])
                run[name] = state, rng.randrange(3_000_000), state == 'passed' and rng.randrange(8) == 0
            runs.append(run)
        expected = []
        for name in runs[-2].keys() | runs[-1].keys():
            before, after = runs[-2].get(name), runs[-1].get(name)
            history = [run[name] for run in runs[:-1] if name in run]
            times = sorted(t for state,t,_ in history if state == 'passed')
            median = times[(len(times)-1)//2] if times else None
            states = {state for state,_,_ in history}
            known = any(flaky for _,_,flaky in history) or ('passed' in states and bool(states & {'failed','errored'}))
            slow = bool(before and after and before[0] == after[0] == 'passed' and median is not None and after[1]*100 > median*150 and after[1]-median >= 200000)
            expected.append({'id':['class','C"[😀]',name], 'category':category(before[0] if before else None, after[0] if after else None), 'baseline_time_us':median, 'known_flaky':known, 'slowdown':slow})
        expected.sort(key=lambda e:(e['category'], json.dumps(e['id'], ensure_ascii=False,separators=(',',':')).encode('utf-16-be')))
        request = {'baselines':[{'xml':xml(run)} for run in runs[:-1]], 'candidate':{'xml':xml(runs[-1])}, 'fail_on':[]}
        jobs.append((request, expected))

    malformed = set()
    while len(malformed) < 1000:
        sample = xml({name:('failed',123,False) for name in rng.sample(names, rng.randint(1,12))})
        mutated = sample[:rng.randrange(1,len(sample))]
        try: ET.fromstring(mutated)
        except ET.ParseError: malformed.add(mutated)
    malformed.update(['<testsuite><testcase name="x"></bad></testsuite>', '<testsuite><testcase name="x" name="y"/></testsuite>', '<testsuite>\x00</testsuite>', '<testsuite><testcase name="&undefined;"/></testsuite>'])
    for text in sorted(malformed):
        try: ET.fromstring(text)
        except ET.ParseError: pass
        else: raise AssertionError('Malformed fixture is valid XML')
        jobs.append(({'op':'parse','document':{'xml':text}}, None))

    checked = 0
    for start in range(0,len(jobs),50):
        batch = jobs[start:start+50]
        data = ''.join(json.dumps(request,ensure_ascii=True)+'\n' for request,_ in batch)
        result = subprocess.run([shutil.which('node') or 'node',str(ROOT/'bin/run.mjs'),str(args.entry.resolve()),'jsonl'],input=data,capture_output=True,encoding='utf-8',timeout=60)
        assert result.returncode in (0,2), result.stderr
        lines = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(lines) == len(batch)
        for got, (_,expected) in zip(lines,batch):
            if expected is None:
                assert got['ok'] is False and got['exit_code'] == 2, got
            else:
                assert got['ok'] is True and got['exit_code'] == 0, got
                projected = [{key:entry[key] for key in ['id','category','baseline_time_us','known_flaky','slowdown']} for entry in got['report']['entries']]
                assert projected == expected, (projected,expected)
                assert got['report']['counts'] == dict(Counter(e['category'] for e in expected))
            checked += 1
    summary={'seed':SEED,'independent_comparisons':500,'malformed_xml':len(malformed),'total':checked,'status':'passed'}
    (ROOT/'_build').mkdir(exist_ok=True)
    (ROOT/'_build/robustness.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary))


if __name__ == '__main__':
    if not __debug__: raise SystemExit('Run without -O; assertions are required')
    main()
