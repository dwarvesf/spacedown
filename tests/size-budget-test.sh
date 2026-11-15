#!/usr/bin/env bash
# size-budget-test.sh: scripts/size-budget passes a small app and dmg, and fails an oversized
# one (the negative control: a sparse fake file, so no disk is spent).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUDGET="$ROOT/scripts/size-budget"
T="$(mktemp -d "${TMPDIR:-/tmp}/size-budget-test.XXXXXX")"
pass=0; fail=0
ok() { echo "  ok   $1"; pass=$((pass + 1)); }
no() { echo "  FAIL $1"; fail=$((fail + 1)); }

mkdir -p "$T/small.app/Contents" "$T/big.app/Contents"
head -c 1500000 /dev/zero > "$T/small.app/Contents/blob"
head -c 1000 /dev/zero > "$T/big.app/Contents/blob"
truncate -s 2400000 "$T/big.app/Contents/oversized"
head -c 900000 /dev/zero > "$T/small.dmg"
truncate -s 1400000 "$T/big.dmg"

if "$BUDGET" "$T/small.app" >/dev/null 2>&1; then ok "1.5 MB app passes"; else no "1.5 MB app passes"; fi
if "$BUDGET" "$T/small.app" "$T/small.dmg" >/dev/null 2>&1; then ok "app and 0.9 MB dmg pass"; else no "app and 0.9 MB dmg pass"; fi
OUT="$("$BUDGET" "$T/big.app" 2>&1)"; rc=$?
if [[ $rc -eq 1 && "$OUT" == *"FAIL app is"* && "$OUT" == *"oversized"* ]]; then ok "2.4 MB app fails and names the biggest file"; else no "2.4 MB app fails and names the biggest file (rc=$rc)"; fi
OUT="$("$BUDGET" "$T/small.app" "$T/big.dmg" 2>&1)"; rc=$?
if [[ $rc -eq 1 && "$OUT" == *"FAIL dmg is"* ]]; then ok "1.4 MB dmg fails"; else no "1.4 MB dmg fails (rc=$rc)"; fi
"$BUDGET" "$T/missing.app" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 64 ]]; then ok "a missing app is a usage error"; else no "a missing app is a usage error (rc=$rc)"; fi

echo "size-budget-test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
