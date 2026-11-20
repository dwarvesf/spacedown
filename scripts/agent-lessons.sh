#!/usr/bin/env bash
# agent-lessons.sh - print the repo lesson index for a coding agent.
#
#   bash scripts/agent-lessons.sh            print .claude/memory/MEMORY.md
#   bash scripts/agent-lessons.sh --verify   check the index instead of printing it
#
# The Claude Code SessionStart hook in .claude/settings.json runs the first form,
# and plain stdout from that hook becomes context. Any agent can run it by hand.
# The first form always exits 0: a missing index must never block a session.
# --verify exits 1 when the index is over 10,000 characters (Claude Code shows
# only a 2,000 character preview of longer hook output), or links a note that
# does not exist, or a note has no name and description in its frontmatter, or a
# note is not linked from the index.
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
dir="$root/.claude/memory"
index="$dir/MEMORY.md"

if [ "${1-}" != "--verify" ]; then
    [ -f "$index" ] && cat "$index"
    exit 0
fi

fails=0
bad() { echo "lessons: $1"; fails=$((fails + 1)); }
[ -f "$index" ] || { echo "lessons: $index is missing"; exit 1; }
size="$(wc -c <"$index" | tr -d ' ')"
[ "$size" -lt 10000 ] || bad "MEMORY.md is $size characters; keep it under 10,000"
links="$(grep -o '([a-z0-9][a-z0-9-]*\.md)' "$index" | tr -d '()')"
for n in $links; do
    [ -f "$dir/$n" ] || bad "MEMORY.md links $n, which does not exist"
done
for f in "$dir"/*.md; do
    n="$(basename "$f")"
    [ "$n" = "MEMORY.md" ] && continue
    printf '%s\n' "$links" | grep -qx "$n" || bad "$n is not linked from MEMORY.md"
    head -n 1 "$f" | grep -q '^---$' || bad "$n has no frontmatter"
    grep -q '^name: ' "$f" || bad "$n has no name line"
    grep -q '^description: ' "$f" || bad "$n has no description line"
    chars="$(wc -c <"$f" | tr -d ' ')"
    [ "$chars" -le 1500 ] || bad "$n is $chars characters; keep a note short (fact, why, how to apply)"
done
[ "$fails" -eq 0 ] && echo "lessons: index ok ($size characters)"
[ "$fails" -eq 0 ]
