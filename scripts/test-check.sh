#!/usr/bin/env bash
# test-check.sh - keep scripts/check.sh and AGENTS.md saying the same thing.
#
#   1. check.sh --help exits 0; a bad option exits 2
#   2. check.sh runs every command AGENTS.md lists as a unit test or a lint
#   3. AGENTS.md and docs/dev/testing.md point at scripts/check.sh
#   4. the settings file wires the guard and the lesson index
# Runs no check itself, so it is fast. bash 3.2 safe.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }

rc=0
bash scripts/check.sh --help >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "--help exits 0"; else bad "--help exited $rc"; fi
rc=0
bash scripts/check.sh --nope >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "a bad option exits 2"; else bad "a bad option exited $rc, expected 2"; fi

for cmd in "tests/smoke.sh" "tests/katex-one-test.sh" "tests/size-budget-test.sh" "tests/hljs-bundle-test.js" "actionlint" "scripts/test-agent-guard.sh" "scripts/test-agent-kit-hook.sh"; do
    if grep -Fq -- "$cmd" scripts/check.sh; then ok "check.sh runs $cmd"; else bad "check.sh does not run $cmd"; fi
done

for cmd in "tests/smoke.sh" "tests/katex-one-test.sh" "tests/size-budget-test.sh" "tests/hljs-bundle-test.js" "actionlint"; do
    if grep -Fq -- "$cmd" AGENTS.md; then ok "AGENTS.md lists $cmd"; else bad "AGENTS.md does not list $cmd"; fi
done

for doc in AGENTS.md docs/dev/testing.md; do
    if grep -Fq -- "scripts/check.sh" "$doc"; then ok "$doc points at scripts/check.sh"; else bad "$doc does not mention scripts/check.sh"; fi
done

if grep -Fq "scripts/agent-guard.sh" .claude/settings.json && grep -Fq "scripts/agent-lessons.sh" .claude/settings.json; then
    ok "settings.json wires the guard and the lesson index"
else
    bad "settings.json does not wire scripts/agent-guard.sh and scripts/agent-lessons.sh"
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
