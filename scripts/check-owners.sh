#!/usr/bin/env bash
# check-owners.sh: fail when a script or workflow has no owner line in
# .github/CODEOWNERS, or a line there is broken. CI runs it on every PR.
#
#   bash scripts/check-owners.sh [<repo root>]
#
# A script is every tracked file under scripts/, bin/ and .github/workflows/
# (Markdown aside), plus every tracked *.sh, *.py and *.mjs outside docs/ (proof
# folders keep dated helper scripts). Each needs its own line, `/<path> @owner`:
# the catch-all `*` line does not count, so a new script cannot slip in unowned.
# Also checked: every line names an owner, and every line without a wildcard
# points at a tracked path. Exit 1 lists each offender. Runs under bash 3.2.
set -euo pipefail
cd "${1:-$(dirname "$0")/..}"

OWNERS=.github/CODEOWNERS
if [ ! -f "$OWNERS" ]; then
    echo "owners: $OWNERS is missing" >&2
    exit 1
fi

failures=""
add_failure() { failures="${failures}  $1
"; }

tracked="$(git ls-files)"
scripts="$(printf '%s\n' "$tracked" | awk '
    /\.md$/ { next }
    /^(scripts|bin|\.github\/workflows)\// { print; next }
    /^docs\// { next }
    /\.(sh|py|mjs)$/ { print }')"

# Exact lines: "/path" with no wildcard. Each line needs an owner.
exact=""
while read -r pattern owner _rest; do
    case "$pattern" in "" | \#*) continue ;; esac
    if [ -z "${owner-}" ]; then
        add_failure "line without an owner: $pattern"
        continue
    fi
    case "$pattern" in
    *\**) continue ;;
    /*)
        path="${pattern#/}"
        path="${path%/}"
        if ! printf '%s\n' "$tracked" | grep -Fxq -- "$path" &&
            ! printf '%s\n' "$tracked" | grep -Fq -- "$path/"; then
            add_failure "line names a path that is not tracked: $pattern"
        fi
        exact="${exact}${path}
"
        ;;
    *) add_failure "line is not anchored with a leading /: $pattern" ;;
    esac
done <"$OWNERS"

count=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count + 1))
    if ! printf '%s' "$exact" | grep -Fxq -- "$f"; then
        add_failure "no owner line: $f (add: /$f @<owner>)"
    fi
done <<EOF
$scripts
EOF

if [ -n "$failures" ]; then
    echo "owners: FAIL ($OWNERS)" >&2
    printf '%s' "$failures" >&2
    exit 1
fi
echo "owners: $count scripts and workflows, all owned"
