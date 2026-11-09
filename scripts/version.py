"""Read the release version from moon.mod and check the compiled constant."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read_version():
    match = re.search(r'^version = "(\d+\.\d+\.\d+)"$', (ROOT/'moon.mod').read_text(encoding='utf-8'), re.M)
    if not match: raise ValueError('Invalid module release version')
    return match.group(1)


if __name__ == '__main__':
    version = read_version()
    if f'"{version}"' not in (ROOT/'version.mbt').read_text(encoding='utf-8'):
        raise SystemExit('version.mbt differs from moon.mod')
    print(version)
