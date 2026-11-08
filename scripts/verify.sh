#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MOON_WORK=off
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon info
moon build cmd/junit_delta --target js --release --deny-warn
node scripts/e2e.mjs
node scripts/scenarios.mjs
node scripts/contract.mjs
node scripts/schema.mjs
node scripts/package-cli.mjs
bash scripts/verify-package.sh
printf '%s\n' 'All source, CLI, oracle and package checks passed.'
