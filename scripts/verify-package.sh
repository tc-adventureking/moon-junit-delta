#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/junit-delta-package.XXXXXXXX")
scratch=$(realpath "$scratch")
case "$scratch" in /|"$repo"|"$repo"/*) exit 1 ;; esac
trap 'rm -rf -- "$scratch"' EXIT
export MOON_WORK=off
cd "$repo"
moon package > "$scratch/package.log" 2>&1 || { cat "$scratch/package.log"; exit 1; }
cat "$scratch/package.log"
mapfile -t archives < <(sed -n 's/^Package to //p' "$scratch/package.log")
test "${#archives[@]}" -eq 1
archive=$(realpath "${archives[0]}")
case "$archive" in "$repo/_build/"*) ;; *) exit 1 ;; esac
unzip -tq "$archive"
unzip -Z1 "$archive" > "$scratch/members.txt"
node --input-type=module - "$scratch/members.txt" <<'NODE'
import { readFileSync } from 'node:fs';
const names=readFileSync(process.argv[2],'utf8').trim().split('\n');
if(new Set(names).size!==names.length) throw Error('Duplicate ZIP members');
for(const name of names) {
  if(name.startsWith('/') || /[\\:\r]/.test(name) || name.split('/').some(p=>p==='..'||p.startsWith('.')||['_build','work','node_modules','__pycache__'].includes(p)) || /\.(py|pyc|pem|key)$/.test(name)) throw Error(`Unexpected ZIP member ${name}`);
}
for(const required of ['moon.mod','moon.pkg','pkg.generated.mbti','LICENSE','README.md','docs/COMPATIBILITY.md','third_party/xml-LICENSE']) {
  if(!names.includes(required)) throw Error(`Missing ${required}`);
}
NODE
unzip -q "$archive" -d "$scratch/library"
moon -C "$scratch/library" check --target all --deny-warn
mkdir "$scratch/consumer"
cp "$repo/examples/consumer/"*.mbt "$repo/examples/consumer/moon.mod" "$repo/examples/consumer/moon.pkg" "$scratch/consumer/"
printf '%s\n' 'members = ["library", "consumer"]' > "$scratch/moon.work"
export MOON_WORK="$scratch/moon.work"
moon -C "$scratch/consumer" test . --target all --deny-warn
moon -C "$scratch/consumer" run . --target wasm-gc --frozen
cat > "$scratch/consumer/immutable.mbt" <<'MOON'
test "external mutation must not compile" {
  let report = @delta.parse_report("<testsuite><testcase name='x'/></testsuite>")
  report.cases[0].final_results.push("failure")
}
MOON
if moon -C "$scratch/consumer" check --target all > "$scratch/immutable.log" 2>&1; then
  printf '%s\n' 'Public result array unexpectedly permits mutation' >&2
  exit 1
fi
# Require the intended compiler rejection, not an unrelated missing dependency.
grep -q 'ReadOnlyArray' "$scratch/immutable.log"
grep -q 'push' "$scratch/immutable.log"
printf '%s\n' 'Fresh source ZIP and independent consumer passed on four targets.'
