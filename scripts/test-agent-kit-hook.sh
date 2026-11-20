#!/usr/bin/env bash
# test-agent-kit-hook.sh - the kit hooks in .claude/settings.json must be no-ops
# for a contributor without the kit, and must pass arguments, stdin and the exit
# code through for a maintainer who has it.
#
#   1. no settings command names the kit directly (all go through the wrapper)
#   2. every settings command exits 0 and prints nothing with HOME set to an empty
#      directory (the wrapper ones; agent-lessons prints the lesson index on purpose)
#   3. with a fake kit: arguments, stdin and the exit code reach the hook
#   4. with AGENT_TEST_REAL_KIT=1 and the real kit installed: every wrapper command
#      runs from a scratch git repo and exits 0
# Needs jq or python3 to read the settings file. bash 3.2 safe.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REAL_HOME="$HOME"
unset DWARVES_KIT_DIR
SETTINGS=".claude/settings.json"
WRAP="$ROOT/scripts/agent-kit-hook.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-hook-test.XXXXXX")"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }

commands() { # every hook command in the settings file, one per line
    if command -v jq >/dev/null 2>&1; then
        jq -r '.hooks[][].hooks[].command' "$SETTINGS"
    else
        python3 -c 'import json
d = json.load(open(".claude/settings.json"))
for groups in d["hooks"].values():
    for g in groups:
        for h in g["hooks"]:
            print(h["command"])'
    fi
}
CMDS="$(commands)" || {
    echo "test-agent-kit-hook: cannot read $SETTINGS" >&2
    exit 2
}

label() { printf '%s' "$1" | sed 's/.*scripts\///; s/"//g'; }

# 1. nothing calls the kit directly
if printf '%s\n' "$CMDS" | grep -q 'dwarves-kit'; then
    bad "a settings command names dwarves-kit directly: $(printf '%s\n' "$CMDS" | grep 'dwarves-kit' | head -1)"
else
    ok "no settings command names dwarves-kit directly"
fi
if printf '%s\n' "$CMDS" | grep -q 'agent-kit-hook.sh'; then
    ok "the kit hooks go through scripts/agent-kit-hook.sh"
else
    bad "no settings command uses scripts/agent-kit-hook.sh"
fi

# 2. an empty HOME: every command exits 0 and the wrapper ones print nothing
EMPTY="$T/empty-home"
mkdir -p "$EMPTY"
n=0
while IFS= read -r c; do
    [ -n "$c" ] || continue
    n=$((n + 1))
    rc=0
    HOME="$EMPTY" CLAUDE_PROJECT_DIR="$ROOT" bash -c "$c" </dev/null >"$T/out" 2>"$T/err" || rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "empty HOME: exit $rc: $c"
        continue
    fi
    case "$c" in
    *agent-kit-hook.sh*)
        if [ -s "$T/out" ] || [ -s "$T/err" ]; then bad "empty HOME: not silent: $c"; else ok "empty HOME: silent exit 0: $(label "$c")"; fi
        ;;
    *) ok "empty HOME: exit 0: $(label "$c")" ;;
    esac
done <<EOF
$CMDS
EOF
[ "$n" -gt 0 ] || bad "the settings file has no commands"

# 3. a fake kit: the wrapper hands over arguments, stdin and the exit code
KIT="$T/kit"
mkdir -p "$KIT/hooks"
cat >"$KIT/hooks/anchor-root.sh" <<'EOF'
#!/bin/bash
echo "anchor:$*"
EOF
out="$(printf 'payload' | DWARVES_KIT_DIR="$KIT" bash "$WRAP" harvest.sh --lab-log 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    ok "kit present, hook file missing: silent exit 0"
else
    bad "kit present, hook file missing: rc $rc out '$out'"
fi
: >"$KIT/hooks/harvest.sh"
out="$(printf 'payload' | DWARVES_KIT_DIR="$KIT" bash "$WRAP" harvest.sh --lab-log 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "anchor:$KIT/hooks/harvest.sh --lab-log" ]; then
    ok "kit present: anchor-root.sh gets the hook path and its arguments"
else
    bad "kit present: rc $rc out '$out'"
fi
cat >"$KIT/hooks/anchor-root.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
bash "$1"
EOF
cat >"$KIT/hooks/echo-stdin.sh" <<'EOF'
#!/bin/bash
echo "exit-seven"
exit 7
EOF
out="$(printf 'payload' | DWARVES_KIT_DIR="$KIT" bash "$WRAP" echo-stdin.sh 2>&1)"
rc=$?
if [ "$rc" -eq 7 ] && [ "$out" = "exit-seven" ]; then
    ok "kit present: the hook's exit code and output pass through"
else
    bad "kit present: expected exit 7, got $rc out '$out'"
fi
cat >"$KIT/hooks/anchor-root.sh" <<'EOF'
#!/bin/bash
echo "stdin:$(cat)"
EOF
out="$(printf 'payload' | DWARVES_KIT_DIR="$KIT" bash "$WRAP" harvest.sh 2>&1)"
if [ "$out" = "stdin:payload" ]; then ok "kit present: stdin reaches the kit"; else bad "kit present: stdin lost: '$out'"; fi
for odd in "" "../x.sh" "a/b.sh"; do
    out="$(DWARVES_KIT_DIR="$KIT" bash "$WRAP" "$odd" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "odd hook name '$odd': silent exit 0"; else bad "odd hook name '$odd': rc $rc out '$out'"; fi
done

# 4. the real kit, when asked for and present. The kit hooks write state under HOME,
# so a plain run never touches it: AGENT_TEST_REAL_KIT=1 opts in.
if [ -n "${AGENT_TEST_REAL_KIT-}" ] && [ -f "$REAL_HOME/.claude/dwarves-kit/hooks/anchor-root.sh" ]; then
    SCRATCH="$T/scratch-repo"
    mkdir -p "$SCRATCH"
    git -C "$SCRATCH" init -q
    while IFS= read -r c; do
        case "$c" in *agent-kit-hook.sh*) ;; *) continue ;; esac
        rc=0
        (cd "$SCRATCH" && echo '{}' | CLAUDE_PROJECT_DIR="$ROOT" bash -c "$c" >/dev/null 2>"$T/err") || rc=$?
        if [ "$rc" -eq 0 ]; then ok "real kit: exit 0: $(label "$c")"; else bad "real kit: exit $rc: $c"; fi
    done <<EOF
$CMDS
EOF
else
    echo "skip  real kit: set AGENT_TEST_REAL_KIT=1 on a machine that has the kit"
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
