#!/usr/bin/env bash
# pr-shape.sh: check the shape of one pull request. CI runs it on every PR
# (.github/workflows/pr-shape.yml); you can run it by hand from a checkout.
#
#   PR_TITLE='fix(cli): short subject' PR_BODY="$(cat body.md)" \
#     BASE_SHA=<base sha> HEAD_SHA=<head sha> bash scripts/pr-shape.sh
#
# Checks, each printed as ok or FAIL with a fix:
#   1. title  a conventional commit subject: type(scope): subject, type one of
#             feat fix refactor docs test chore ci, scope optional, 72 characters
#             or less. The squash merge makes it the commit subject on main.
#   2. proof  a body line `no-proof: <reason of 10+ characters>`, or a proof file
#             docs/verification/<slug>.md (not README.md) in the diff that holds
#             an `Exit:` line, a line starting `Verdict: RED` and the words
#             "negative control". A behavior change (any changed file that is not
#             documentation) needs one of the two; so does a docs-only PR, which
#             writes the no-proof line.
#   3. issue  when the body claims an issue (Closes, Fixes or Resolves, in any
#             form, followed by #, "issue #" or a GitHub URL), the claim names a
#             real reference: #<n> or a github.com/<owner>/<repo>/issues/<n> URL.
#             The template placeholder `Closes #<n>` fails.
#
# HTML comments are removed from the body first: the template's hints are not
# the author's words. The script reads only git objects (BASE_SHA...HEAD_SHA in
# the current directory) and the variables above, so CI can run the base
# branch's copy against a PR checkout. Exit 0 when all pass, 1 on a failure,
# 2 on bad usage. Runs under bash 3.2.
set -uo pipefail

title="${PR_TITLE-}"
body="${PR_BODY-}"
if [ -z "${BASE_SHA-}" ] || [ -z "${HEAD_SHA-}" ]; then
    echo "pr-shape: set BASE_SHA and HEAD_SHA (and PR_TITLE, PR_BODY)" >&2
    exit 2
fi
if ! changed="$(git -c core.quotePath=false diff --no-ext-diff --no-textconv --name-only --diff-filter=d "$BASE_SHA...$HEAD_SHA" 2>&1)"; then
    echo "pr-shape: git diff $BASE_SHA...$HEAD_SHA failed: $changed" >&2
    exit 2
fi

fails=0
ok() { printf 'ok    %s\n' "$1"; }
fail() { # fail <what is wrong> <how to fix it>
    printf 'FAIL  %s\n      fix: %s\n' "$1" "$2"
    fails=$((fails + 1))
}

body="$(printf '%s\n' "$body" | tr -d '\r' | perl -0pe 's/<!--.*?-->//gs')"

# Documentation, as the optional kit's proof gate counts it: Markdown and text
# anywhere, .kit.toml, and images or PDFs under docs/. A path that looks like a
# secret never counts as documentation.
nondoc_paths() {
    awk '{ lc = tolower($0) }
        lc ~ /(^|\/)[^\/]*credentials?[^\/]*$|(^|\/)secrets?\/|\.(pem|key|p12|pfx)$|(^|\/)\.env/ { print; next }
        $0 ~ /\.(md|txt|markdown)$/ || $0 ~ /(^|\/)\.kit\.toml$/ { next }
        $0 ~ /(^|\/)docs\// && $0 ~ /\.(rst|adoc|png|jpe?g|gif|webp|pdf|csv)$/ { next }
        $0 ~ /^docs\// && $0 ~ /\.(html?|svg)$/ { next }
        { print }'
}
behavior=0
if [ -n "$(printf '%s\n' "$changed" | sed '/^$/d' | nondoc_paths)" ]; then behavior=1; fi

# 1. title
title_re='^(feat|fix|refactor|docs|test|chore|ci)(\([a-z0-9._/-]+\))?: [^ ].*$'
if [[ "$title" =~ $title_re ]] && [ "${#title}" -le 72 ]; then
    ok "title: a conventional commit subject"
else
    fail "title: \"$title\" is not type(scope): subject with type feat, fix, refactor, docs, test, chore or ci and 72 characters or less (${#title} now)" \
        "rename the PR, for example: gh pr edit <number> --title 'fix(cli): short subject'"
fi

# 2. proof
noproof_reason=""
while IFS= read -r line; do
    case "$line" in
    no-proof:*)
        reason="${line#no-proof:}"
        reason="${reason#"${reason%%[![:space:]]*}"}"
        if [ "${#reason}" -ge 10 ]; then noproof_reason="$reason"; fi
        ;;
    esac
done <<EOF
$body
EOF
proof_missing() { # proof_missing <path>: one missing part per line, nothing when complete
    local text
    text="$(git show "$HEAD_SHA:$1" 2>/dev/null | tr -d '\r')"
    printf '%s\n' "$text" | grep -Eq '^[[:space:]]*Exit:' ||
        echo 'an "Exit:" line (the real exit code of a command)'
    printf '%s\n' "$text" | grep -Eq '^[[:space:]]*Verdict: RED' ||
        echo 'a line that starts "Verdict: RED" (the end of the negative control block)'
    printf '%s\n' "$text" | grep -Eiq 'negative control' ||
        echo 'the words "negative control"'
}
proof_good=""
proof_report=""
while IFS= read -r f; do
    case "$f" in
    docs/verification/README.md | docs/verification/*/*) continue ;;
    docs/verification/*.md) ;;
    *) continue ;;
    esac
    miss="$(proof_missing "$f")"
    if [ -z "$miss" ]; then
        proof_good="$f"
        break
    fi
    proof_report="${proof_report}      $f lacks:
$(printf '%s\n' "$miss" | sed 's/^/        - /')
"
done <<EOF
$changed
EOF
howto="docs/verification/README.md says how to write one"
if [ -n "$noproof_reason" ]; then
    ok "proof: skipped by the body line no-proof: $noproof_reason"
elif [ -n "$proof_good" ]; then
    ok "proof: $proof_good has an Exit line, a negative control and Verdict: RED"
elif [ -n "$proof_report" ]; then
    fail "proof: no proof file in this PR holds the blocks this check reads" \
        "complete one of these files ($howto). Missing:"
    printf '%s' "$proof_report"
elif [ "$behavior" -eq 1 ]; then
    fail "proof: a behavior path changed and the PR adds or changes no proof file under docs/verification/" \
        "add docs/verification/<slug>.md with a green run and a negative control that ends 'Verdict: RED, as expected' ($howto). A change with no behavior effect (config only, a comment) puts a body line no-proof: <reason, 10+ characters>"
else
    fail "proof: a docs-only PR without a no-proof line" \
        "add a body line no-proof: <reason, 10+ characters>, for example: no-proof: docs only, no behavior change"
fi

# 3. issue link, only when the body claims one. A claim is a closing keyword
# followed by "#", "issue #" or a GitHub URL; plain prose ("fixes the gap") is
# not a claim. Each claim's reference must be #<n> or an issues/<n> URL.
claim_re='(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+(issue[[:space:]]+)?(#|https?://github\.com/)[^[:space:]]*'
good_ref_re='(#[0-9]+|https?://github\.com/[a-z0-9_.-]+/[a-z0-9_.-]+/issues/[0-9]+)[.,;:)]*$'
claims="$(printf '%s\n' "$body" | tr '[:upper:]' '[:lower:]' | grep -oE "$claim_re" || true)"
bad_claims=""
n_claims=0
while IFS= read -r c; do
    [ -n "$c" ] || continue
    n_claims=$((n_claims + 1))
    if ! printf '%s\n' "$c" | grep -Eq "$good_ref_re"; then
        bad_claims="${bad_claims}      ${c#[^[:alnum:]]}
"
    fi
done <<EOF
$claims
EOF
if [ "$n_claims" -eq 0 ]; then
    ok "issue: the body claims no issue"
elif [ -z "$bad_claims" ]; then
    ok "issue: every claimed issue is a #<n> or an issue URL"
else
    fail "issue: the body claims an issue without a real reference" \
        "write the number, for example: Closes #12, or remove the claim. Claims:"
    printf '%s' "$bad_claims"
fi

echo "pr-shape: $fails failed"
[ "$fails" -eq 0 ]
