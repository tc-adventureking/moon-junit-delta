"""Verify release hashes and safely extract the portable CLI into a new directory."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from version import read_version
VERSION = read_version()

if not __debug__:
    raise SystemExit('Run without -O or PYTHONOPTIMIZE; archive verification requires assertions')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archives', type=Path)
parser.add_argument('--extract-cli', type=Path, required=True)
args = parser.parse_args()
manifest = json.loads((args.archives / 'RELEASE.json').read_text(encoding='utf-8'))
assert manifest['version'] == VERSION
expected = {f'junit-delta-{VERSION}-source.zip', f'tc-adventureking-junit_delta-{VERSION}.zip', f'junit-delta-{VERSION}-cli.zip'}
assert {x['file'] for x in manifest['archives']} == expected and len(manifest['archives']) == 3
assert not args.extract_cli.exists(), 'Choose a new extraction directory'
for item in manifest['archives']:
    archive = args.archives / item['file']
    assert archive.stat().st_size == item['bytes']
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256']
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert len(z.namelist()) == len(set(z.namelist()))
        for name in z.namelist():
            assert not name.startswith('/') and '\\' not in name and ':' not in name and '..' not in name.split('/')
            assert not (set(name.split('/')) & {'work', '.git', '.mooncakes', '_build', 'node_modules', '__pycache__'})
            if item['file'].endswith('-cli.zip'):
                assert name.startswith(f'junit-delta-{VERSION}-cli/')
        if item['file'].endswith('-cli.zip'):
            z.extractall(args.extract_cli)
root = args.extract_cli / f'junit-delta-{VERSION}-cli'
assert not (root / 'moon.mod').exists()
files = json.loads((root / 'MANIFEST.json').read_text(encoding='utf-8'))['files']
assert len({x['path'] for x in files}) == len(files)
assert {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()} == {'MANIFEST.json'} | {x['path'] for x in files}
for item in files:
    path = (root / item['path']).resolve()
    assert path.is_relative_to(root.resolve())
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
print('Three release archives and all portable files verified:', root)
