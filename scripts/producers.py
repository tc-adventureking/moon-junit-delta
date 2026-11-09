"""Generate real pytest, Surefire and Node reports and verify their public APIs.

Raw reports and producer logs may contain machine paths. They stay in _build;
only the compact, path-free verification summary is printed or archived by CI.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    'legacy': {'pytest': '8.4.2', 'surefire': '3.5.4', 'junit': '5.11.4'},
    'current': {'pytest': '9.2.0', 'surefire': '3.6.1', 'junit': '6.1.3'},
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=PROFILES, default='current')
    parser.add_argument('--only', choices=['all', 'pytest', 'surefire', 'node'], default='all')
    parser.add_argument('--pytest-python', default=sys.executable)
    parser.add_argument('--entry', type=Path, default=ROOT/'_build/js/release/build/cmd/junit_delta/junit_delta.js')
    args = parser.parse_args()
    versions = PROFILES[args.profile]
    output = ROOT/'_build/producers'
    output.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix=f'{args.profile}-{args.only}-', dir=output))
    runtime = [shutil.which('node') or 'node', str(ROOT/'bin/run.mjs'), str(args.entry.resolve()), 'jsonl']
    sequence = 0

    def execute(command, *, cwd=scratch, env=None, accepted=(0,), input=None, timeout=180):
        nonlocal sequence
        sequence += 1
        result = subprocess.run(command, cwd=cwd, env=env, input=input, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=timeout)
        (scratch/f'command-{sequence}.log').write_text(result.stdout+'\n'+result.stderr, encoding='utf-8')
        if result.returncode not in accepted:
            raise RuntimeError(f'Producer command {sequence} returned {result.returncode}; private log: {scratch.name}/command-{sequence}.log')
        return result.stdout

    def request(value, expected_code=0):
        data = execute(runtime, input=json.dumps(value, ensure_ascii=True)+'\n', accepted=(expected_code,))
        result = json.loads(data)
        assert result['ok'] is True, result
        assert result['exit_code'] == expected_code
        return result['report']

    def document(path):
        # Use portable labels, not host paths, in the library's output.
        return {'xml': path.read_text(encoding='utf-8-sig'), 'source': path.name}

    def parse(path):
        return request({'op': 'parse', 'document': document(path)})['cases']

    def compare(before, after):
        return request({'baselines': [document(before)], 'candidate': document(after)}, 1)

    summaries = []
    if args.only in ('all', 'pytest'):
        actual = execute([args.pytest_python, '-c', 'import pytest; print(pytest.__version__)']).strip()
        assert actual == versions['pytest'], (actual, versions['pytest'])
        source = scratch/'pytest-source'
        source.mkdir()
        shutil.copyfile(ROOT/'integration/pytest/test_reports.py', source/'test_reports.py')
        env = {**os.environ, 'PYTEST_DISABLE_PLUGIN_AUTOLOAD': '1', 'PYTHONUTF8': '1'}

        def pytest_report(label, stage, family, expression=None):
            path = scratch/f'{label}.xml'
            command = [args.pytest_python, '-m', 'pytest', 'test_reports.py', '-q',
                       '-p', 'no:cacheprovider', '--confcutdir', str(source), '--rootdir', str(source),
                       '-o', f'junit_family={family}', '--junitxml', str(path)]
            if expression: command += ['-k', expression]
            execute(command, cwd=source, env={**env, 'DELTA_STAGE': stage}, accepted=(0, 1))
            assert path.is_file()
            return path

        for family in ['xunit1', 'xunit2']:
            baseline = pytest_report(f'pytest-{family}-baseline', 'baseline', family)
            current = pytest_report(f'pytest-{family}-candidate', 'candidate', family)
            before = parse(baseline); after = parse(current)
            assert len(before) == len(after) == 10
            outcomes = {c['name']: c['result']['outcome'] for c in after}
            assert outcomes['test_stable'] == 'passed'
            assert outcomes['test_new_failure'] == outcomes['test_persistent_failure'] == 'failed'
            assert outcomes['test_fixed_failure'] == outcomes['test_unexpected_pass'] == 'passed'
            assert outcomes['test_skipped'] == outcomes['test_expected_failure'] == 'skipped'
            assert outcomes['test_setup_error'] == 'errored'
            parameters = [c for c in after if c['name'].startswith('test_parameters[')]
            assert len(parameters) == 2 and Counter(c['result']['outcome'] for c in parameters) == {'passed': 1, 'failed': 1}
            diff = compare(baseline, current)
            expected = {'fixed': 1, 'new_failure': 2, 'still_failing': 2, 'unchanged': 5}
            assert diff['counts'] == expected, diff['counts']
            assert diff['gate']['violations'] == ['new_failure']
            expression = 'parameters or stable or skipped'
            shard_a = pytest_report(f'pytest-{family}-shard-a', 'candidate', family, expression)
            shard_b = pytest_report(f'pytest-{family}-shard-b', 'candidate', family, f'not ({expression})')
            split = request({'baselines': [document(baseline)], 'candidate': [document(shard_a), document(shard_b)]}, 1)
            assert split['counts'] == expected
            assert {(tuple(e['id']), e['category']) for e in split['entries']} == {(tuple(e['id']), e['category']) for e in diff['entries']}
            summaries.append({'producer': 'pytest', 'version': actual, 'family': family,
                              'cases': 10, 'reports': 4, 'shard_equivalence': True, 'counts': expected})

    if args.only in ('all', 'surefire'):
        maven = shutil.which('mvn.cmd' if os.name == 'nt' else 'mvn')
        if not maven: raise RuntimeError('Maven is required for real Surefire integration')
        source = scratch/'maven-source'
        shutil.copytree(ROOT/'integration/surefire', source)
        settings = scratch/'settings.xml'
        settings.write_text('<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"/>', encoding='utf-8')
        cache = ROOT/'_build/producer-cache/maven'
        cache.mkdir(parents=True, exist_ok=True)
        paths = {}
        for stage in ['baseline', 'candidate']:
            command = [maven, '-B', '-ntp', '-q', '-s', str(settings), '-gs', str(settings),
                       f'-Dmaven.repo.local={cache}', f'-Ddelta.stage={stage}',
                       f'-Djunit.version={versions["junit"]}', f'-Dsurefire.version={versions["surefire"]}', 'test']
            execute(command, cwd=source, accepted=(1,), timeout=600)
            report = source/'target/surefire-reports/TEST-example.ReportTest.xml'
            assert report.is_file(), 'Maven failed before producing a report'
            destination = scratch/f'surefire-{stage}.xml'
            shutil.copyfile(report, destination)
            paths[stage] = destination
            cases = parse(destination)
            assert len(cases) == 9, [c['name'] for c in cases]
            named = {c['name']: c for c in cases}
            assert named['stable']['result']['outcome'] == 'passed'
            assert named['skipped']['result']['outcome'] == 'skipped'
            assert named['flaky']['result']['outcome'] == 'passed'
            assert named['flaky']['is_flaky'] and named['flaky']['result']['attempts'] == 2
            assert named['persistentFailure']['result']['outcome'] == 'failed'
            assert named['persistentFailure']['is_rerun'] and named['persistentFailure']['result']['attempts'] == 3
            assert named['error']['result']['outcome'] == 'errored'
            assert named['error']['result']['attempts'] == 3
            assert named['newFailure']['result']['outcome'] == ('failed' if stage == 'candidate' else 'passed')
            assert named['fixedFailure']['result']['outcome'] == ('passed' if stage == 'candidate' else 'failed')
        diff = compare(paths['baseline'], paths['candidate'])
        expected = {'fixed': 1, 'new_failure': 2, 'still_failing': 2, 'unchanged': 4}
        assert diff['counts'] == expected, diff['counts']
        assert diff['gate']['violations'] == ['new_failure']
        summaries.append({'producer': 'surefire', 'version': versions['surefire'], 'junit': versions['junit'],
                          'cases': 9, 'reports': 2, 'native_retries': True, 'counts': expected})

    if args.only in ('all', 'node'):
        paths = {}
        for stage in ['baseline', 'candidate']:
            destination = scratch/f'node-{stage}.xml'
            execute([runtime[0], '--test', '--test-reporter=junit', f'--test-reporter-destination={destination}',
                     str(ROOT/'integration/node/reports.mjs')], env={**os.environ, 'DELTA_STAGE': stage}, accepted=(1,))
            cases = parse(destination)
            assert len(cases) == 4
            assert Counter(c['result']['outcome'] for c in cases) == {'passed': 2, 'failed': 1, 'skipped': 1}
            paths[stage] = destination
        diff = compare(paths['baseline'], paths['candidate'])
        expected = {'fixed': 1, 'new_failure': 1, 'unchanged': 2}
        assert diff['counts'] == expected, diff['counts']
        assert diff['gate']['violations'] == ['new_failure']
        summaries.append({'producer': 'node', 'version': execute([runtime[0], '--version']).strip(),
                          'cases': 4, 'reports': 2, 'counts': expected})

    result = {'profile': args.profile, 'checks': summaries, 'status': 'passed'}
    (output/f'{args.profile}-{args.only}.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    if not __debug__: raise SystemExit('Run without -O so all validation checks execute')
    main()
