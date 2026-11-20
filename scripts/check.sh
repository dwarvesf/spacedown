#!/usr/bin/env bash
# check.sh - the one local command before a push. It runs every check AGENTS.md
# lists and prints one line per check. Needs no plugin. Exit 0: all clear.
# Exit 1: a check failed. Exit 2: bad usage.
#
#   bash scripts/check.sh           everything below; the smoke suite is most of the minute it takes
#   bash scripts/check.sh --quick   skips the smoke suite and runs the render core tests
#                                   directly, for the inner loop; run the full one before the PR
#   bash scripts/check.sh --help
#
# What it runs, in order:
#   1. bash -n on every tests/*.sh and every agent script (CI does this too)
#   2. bash tests/smoke.sh under /bin/bash (bash 3.2, as CI does); must end "smoke: all N passed"
#   3. the unit tests outside smoke: katex-one-test.sh, size-budget-test.sh, hljs-bundle-test.js,
#      plus the owner check and pr-shape-test.sh that CI runs
#   4. the agent harness tests: guard, kit hook wrapper, lesson index
#   5. actionlint, when installed (a missing one is a note, not a failure)
# Not run here: the app build and the live Quick Look panel. A change that needs them
# says so in AGENTS.md. bash 3.2 safe.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

quick=0
case "${1-}" in
--quick) quick=1 ;;
-h | --help)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 0
    ;;
"") ;;
*)
    echo "check: unknown option $1 (use --quick or --help)" >&2
    exit 2
    ;;
esac

fails=0
ok() { printf 'ok    %s\n' "$1"; }
note() { printf 'note  %s\n' "$1"; }
fail() { # fail <reason> <fix>
    printf 'FAIL  %s\n      fix: %s\n' "$1" "$2"
    fails=$((fails + 1))
}

run_step() { # run_step <label> <fix> <command...>: the last 15 lines show on a failure
    local label="$1" fix="$2" out
    shift 2
    if out="$("$@" 2>&1)"; then
        out="$(printf '%s\n' "$out" | tail -n 1)"
        if [ -n "$out" ]; then ok "$label ($out)"; else ok "$label"; fi
    else
        printf '%s\n' "$out" | tail -n 15
        fail "$label" "$fix"
    fi
}

need_node() {
    command -v node >/dev/null 2>&1 && return 0
    fail "node is not installed: the render core, the smoke suite and hljs-bundle-test need it" \
        "brew install node (CONTRIBUTING.md, Prerequisites)"
    return 1
}

# 1. syntax of every shell script a test or a hook runs
syntax() {
    local f bad=0
    for f in tests/*.sh scripts/check.sh scripts/agent-*.sh scripts/test-*.sh; do
        [ -f "$f" ] || continue
        /bin/bash -n "$f" || bad=1
    done
    [ "$bad" -eq 0 ]
}
run_step "bash -n on tests/*.sh and the agent scripts" \
    "fix the syntax error above; the scripts must parse under /bin/bash 3.2" syntax

# 2. the smoke suite, or with --quick the render core tests it includes
smoke() {
    local log rc=0
    log="$(mktemp "${TMPDIR:-/tmp}/check-smoke.XXXXXX")" || return 1
    /bin/bash tests/smoke.sh >"$log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        grep -E '^(FAIL|smoke:)' "$log" | head -15
        return 1
    fi
    grep -Eq '^smoke: all [0-9]+ passed$' "$log" || {
        echo "smoke: the run ended without 'smoke: all N passed'"
        tail -n 5 "$log"
        return 1
    }
    grep -E '^smoke: all [0-9]+ passed$' "$log"
}
render_core() {
    local t rc=0
    for t in test-render test-contract test-boxdraw test-xray test-present; do
        node "integrations/safari/quick-look/$t.js" >/dev/null 2>&1 || {
            echo "$t failed: node integrations/safari/quick-look/$t.js"
            rc=1
        }
    done
    [ "$rc" -eq 0 ] && echo "5 render core tests"
    return "$rc"
}
if [ "$quick" -eq 1 ]; then
    note "--quick: the smoke suite is skipped; run bash scripts/check.sh before you open the PR"
    if need_node; then
        run_step "render core tests" \
            "run the named test with node, read its FAIL lines, fix, rerun" render_core
    fi
elif need_node; then
    run_step "smoke suite (/bin/bash tests/smoke.sh)" \
        "bash tests/smoke.sh --list names the sections; rerun one with --only <section>, fix, rerun all" smoke
fi

# 3. the unit tests outside smoke
run_step "katex-one-test.sh" "read the FAIL lines above; docs/dev/testing.md, row KaTeX" \
    /bin/bash tests/katex-one-test.sh
run_step "size-budget-test.sh" "read the FAIL lines above; docs/dev/testing.md, row Size budget" \
    /bin/bash tests/size-budget-test.sh
if command -v node >/dev/null 2>&1; then
    run_step "hljs-bundle-test.js" "read the FAIL lines above; docs/dev/testing.md, row highlight.js" \
        node tests/hljs-bundle-test.js
fi

# 3b. the repo checks CI runs: owners, and the PR shape script's own test
run_step "owner check" "add the missing line to .github/CODEOWNERS (scripts/check-owners.sh names it)" \
    /bin/bash scripts/check-owners.sh
run_step "pr-shape-test.sh" "read the FAIL lines above; docs/dev/testing.md, row PR shape" \
    /bin/bash scripts/pr-shape-test.sh

# 4. the agent harness
run_step "agent guard test" "read the FAIL lines above; the guard is scripts/agent-guard.sh" \
    /bin/bash scripts/test-agent-guard.sh
run_step "agent kit hook test" "read the FAIL lines above; the wrapper is scripts/agent-kit-hook.sh" \
    /bin/bash scripts/test-agent-kit-hook.sh
run_step "check.sh test" "read the FAIL lines above; AGENTS.md must list what check.sh runs" \
    /bin/bash scripts/test-check.sh
run_step "lesson index" "keep .claude/memory/MEMORY.md under 10,000 characters and link only notes that exist" \
    /bin/bash scripts/agent-lessons.sh --verify

# 5. workflow lint
if command -v actionlint >/dev/null 2>&1; then
    run_step "actionlint" "fix each finding above and rerun actionlint" actionlint
else
    note "actionlint is not installed: brew install actionlint (CI runs it on .github/workflows/)"
fi

note "not run here: the app build (NO_INSTALL=1 integrations/build-safari.sh) and the live Quick Look panel (in a VM or a clean macOS user)"

echo "check: $fails failed"
[ "$fails" -eq 0 ]
