"""Build three deterministic archives from a clean Git checkout; Python stdlib only."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.1.0'


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, env={**os.environ, 'MOON_WORK': 'off'}, stderr=subprocess.STDOUT, text=True, encoding='utf-8').strip()


def safe_name(name):
    parts = PurePosixPath(name).parts
    if not parts or name.startswith('/') or '\\' in name or ':' in name or '..' in parts:
        raise ValueError(f'Unsafe archive path: {name}')
    if set(parts) & {'work', '.git', '.mooncakes', '_build', 'node_modules', '__pycache__'}:
        raise ValueError(f'Private/generated archive path: {name}')
    return name


def archive(path, members):
    names = [safe_name(name) for name, _ in members]
    if len(names) != len(set(names)):
        raise ValueError('Duplicate archive names')
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_STORED) as out:
        for name, data in sorted(members):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            out.writestr(info, data)
    with zipfile.ZipFile(path) as check:
        if check.testzip() is not None:
            raise ValueError('Archive CRC check failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / '_build/archives')
    args = parser.parse_args()
    if command('git', 'status', '--porcelain'):
        raise RuntimeError('Commit source changes before building release archives')
    output = args.output.resolve()
    if output == ROOT:
        raise ValueError('Output must not be the repository root')
    output.mkdir(parents=True, exist_ok=True)
    commit = command('git', 'rev-parse', 'HEAD')
    command('moon', 'build', 'cmd/junit_delta', '--target', 'js', '--release', '--deny-warn')
    print(command('node', 'scripts/package-cli.mjs'))
    log = command('moon', 'package')
    paths = [line.removeprefix('Package to ') for line in log.splitlines() if line.startswith('Package to ')]
    if len(paths) != 1:
        raise RuntimeError(f'Expected one moon package archive: {log}')
    module = (ROOT / paths[0]).resolve()
    if not module.is_relative_to(ROOT / '_build'):
        raise ValueError('Module archive outside build directory')
    full = output / f'junit-delta-{VERSION}-source.zip'
    raw = subprocess.check_output(['git', 'archive', '--format=tar', 'HEAD'], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as source:
        members = []
        for item in source:
            if item.isdir():
                continue
            if not item.isfile():
                raise ValueError(f'Non-regular source entry: {item.name}')
            members.append((f'junit-delta-{VERSION}/' + item.name, source.extractfile(item).read()))
        archive(full, members)
    module_out = output / module.name
    with zipfile.ZipFile(module) as package:
        if package.testzip() is not None:
            raise ValueError('Invalid module ZIP')
        archive(module_out, [(x.filename, package.read(x)) for x in package.infolist() if not x.is_dir()])
    directory = ROOT / f'_build/release/junit-delta-{VERSION}-cli'
    manifest = json.loads((directory / 'MANIFEST.json').read_text(encoding='utf-8'))
    actual = {p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file()}
    if actual != {'MANIFEST.json'} | {x['path'] for x in manifest['files']}:
        raise ValueError('Portable manifest does not cover exactly the shipped files')
    for item in manifest['files']:
        path = directory / safe_name(item['path'])
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError(f'Portable file hash mismatch: {item["path"]}')
    portable = output / f'junit-delta-{VERSION}-cli.zip'
    archive(portable, [(f'junit-delta-{VERSION}-cli/' + name, (directory / name).read_bytes()) for name in actual])
    if command('git', 'status', '--porcelain'):
        raise RuntimeError('Build changed source; commit and verify before releasing')
    records = [{'file':p.name, 'bytes':p.stat().st_size, 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [full, module_out, portable]]
    result = {'project':'junit-delta', 'version':VERSION, 'source_commit':commit,
              'tools':{'moon':command('moon', 'version'), 'node':command('node', '--version'), 'python':sys.version.split()[0]}, 'archives':records}
    (output / 'RELEASE.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    (output / 'SHA256SUMS').write_text(''.join(f'{x["sha256"]}  {x["file"]}\n' for x in records), encoding='utf-8', newline='\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
