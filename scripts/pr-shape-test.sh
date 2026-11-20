#!/usr/bin/env bash
# pr-shape-test.sh: run scripts/pr-shape.sh against a temp git repo, one case per
# line of the list below. No network. CI runs it in the pr-shape job.
#
#   bash scripts/pr-shape-test.sh [<path to pr-shape.sh>]
#
# Each case says what the PR changes, its title and body, and the expected exit
# code (0 pass, 1 fail). The bad-title and missing-proof cases are the negative
# controls: they prove the gate can go red. Prints PASS or FAIL per case and
# "pr-shape-test: N passed, M failed". Runs under bash 3.2.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$here/pr-shape.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
T="$(mktemp -d "${TMPDIR:-/tmp}/pr-shape-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

passed=0
failed=0
R="$T/repo"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
put() { # put <path> <content>
    mkdir -p "$(dirname "$R/$1")"
    printf '%s\n' "$2" >"$R/$1"
}

GOOD_PROOF='# Proof

```
Command: bash tests/smoke.sh
Exit: 0
Output: smoke: all 3 passed
Verdict: PASS
```

## Negative control

```
Command: bash tests/smoke.sh
Exit: 1 (under the mutation)
Verdict: RED, as expected
```'
NO_RED_PROOF='# Proof

```
Command: bash tests/smoke.sh
Exit: 0
Verdict: PASS
```'

mkdir -p "$R"
git -C "$R" init -q --template=
put README.md "readme"
put bin/tool "#!/bin/bash"
put docs/guide.md "guide"
g add -A
g commit -qm base
BASE="$(g rev-parse HEAD)"

# change <kind>: a commit on top of BASE with one kind of change; prints its sha
change() {
    g checkout -q --detach "$BASE"
    case "$1" in
    code) put bin/tool "echo changed" ;;
    code+proof)
        put bin/tool "echo changed"
        put docs/verification/x.md "$GOOD_PROOF"
        ;;
    code+weakproof)
        put bin/tool "echo changed"
        put docs/verification/x.md "$NO_RED_PROOF"
        ;;
    code+readme-only)
        put bin/tool "echo changed"
        put docs/verification/README.md "$GOOD_PROOF"
        ;;
    docs) put docs/guide.md "guide, longer" ;;
    esac
    g add -A
    g commit -qm change
    g rev-parse HEAD
}

# case_ <expected exit> <label> <kind> <title> <body> [<check that must fail>]
case_() {
    local want="$1" label="$2" kind="$3" title="$4" body="$5" check="${6-}" head got out
    head="$(change "$kind")"
    out="$(cd "$R" && PR_TITLE="$title" PR_BODY="$body" BASE_SHA="$BASE" HEAD_SHA="$head" bash "$SCRIPT" 2>&1)"
    got=$?
    if [ -n "$check" ] && ! printf '%s\n' "$out" | grep -q "^FAIL  $check:"; then
        echo "FAIL  $label: no FAIL line for the $check check"
        printf '%s\n' "$out" | sed 's/^/      /'
        failed=$((failed + 1))
    elif [ "$got" -eq "$want" ]; then
        echo "PASS  $label (exit $got)"
        passed=$((passed + 1))
    else
        echo "FAIL  $label: want exit $want, got $got"
        printf '%s\n' "$out" | sed 's/^/      /'
        failed=$((failed + 1))
    fi
}

TEMPLATE_BODY='## What
<!-- One or two sentences. Link the issue: Closes #<n>. -->
Adds a flag.

## Proof
<!-- A docs-only PR writes "no-proof: docs only". -->
docs/verification/x.md'
T72="docs: $(printf 'a%.0s' $(seq 1 66))"
T73="docs: $(printf 'a%.0s' $(seq 1 67))"

# Green cases
case_ 0 "behavior change with a full proof file" code+proof "feat(cli): add a flag" "$TEMPLATE_BODY"
case_ 0 "docs change with a no-proof line" docs "docs: fix a typo" "no-proof: docs only, no behavior change"
case_ 0 "config change with a no-proof line" code "chore(ci): bump a pin" "no-proof: config only, CI covers it"
case_ 0 "valid issue claims" code+proof "fix: a bug" "Closes #12
Fixes https://github.com/o/r/issues/3."
case_ 0 "prose that says fixes is not a claim" code+proof "fix: a bug" "This fixes the table gap."
case_ 0 "template comments are ignored" code+proof "fix: a bug" "$TEMPLATE_BODY"
case_ 0 "title of exactly 72 characters" docs "$T72" "no-proof: docs only, no behavior change"

# Negative controls: each must fail
case_ 1 "bad title: no type" code+proof "Add a flag" "" title
case_ 1 "bad title: unknown type" code+proof "feature: add a flag" "" title
case_ 1 "bad title: 73 characters" docs "$T73" "no-proof: docs only, no behavior change" title
case_ 1 "missing proof on a behavior change" code "feat(cli): add a flag" "Adds a flag." proof
case_ 1 "proof file without a negative control" code+weakproof "feat(cli): add a flag" "" proof
case_ 1 "README.md is not a proof file" code+readme-only "feat(cli): add a flag" "" proof
case_ 1 "docs-only PR without a no-proof line" docs "docs: fix a typo" "" proof
case_ 1 "no-proof reason under 10 characters" code "chore: x" "no-proof: config" proof
case_ 1 "placeholder issue claim" code+proof "fix: a bug" "Closes #<n>" issue
case_ 1 "issue claim with a PR URL" code+proof "fix: a bug" "Fixes https://github.com/o/r/pull/3" issue

# Bad usage
(cd "$R" && PR_TITLE=x bash "$SCRIPT" >/dev/null 2>&1)
got=$?
if [ "$got" -eq 2 ]; then
    echo "PASS  missing BASE_SHA exits 2"
    passed=$((passed + 1))
else
    echo "FAIL  missing BASE_SHA: want exit 2, got $got"
    failed=$((failed + 1))
fi

echo "pr-shape-test: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
