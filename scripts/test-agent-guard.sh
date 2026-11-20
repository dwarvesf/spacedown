#!/usr/bin/env bash
# test-agent-guard.sh - feed canned hook JSON to agent-guard.sh and check the exit
# code (2 blocks, 0 allows) and that a block names the fix. Temp git repos stand in
# for "on main", "on a feature branch" and "on a contract branch". No network.
# Also checks scripts/agent-frozen-paths.txt against docs/contract-r1.md.
# Leaves its temp dir behind (the repo never deletes); the path is printed.
# bash 3.2 safe. jq or python3 builds the JSON.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
GUARD="$ROOT/scripts/agent-guard.sh"
LIST="$ROOT/scripts/agent-frozen-paths.txt"
T="$(mktemp -d "${TMPDIR:-/tmp}/agent-guard-test.XXXXXX")"
echo "test dir: $T"

mkjson() { # mkjson <tool> <cwd> <command-or-path>
    if command -v jq >/dev/null 2>&1; then
        case "$1" in
        Bash) jq -n --arg d "$2" --arg c "$3" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' ;;
        *) jq -n --arg t "$1" --arg d "$2" --arg p "$3" '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$d,tool_input:{file_path:$p}}' ;;
        esac
    else
        python3 -c 'import json,sys
tool, cwd, val = sys.argv[1:4]
ti = {"command": val} if tool == "Bash" else {"file_path": val}
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": cwd, "tool_input": ti}))' "$1" "$2" "$3"
    fi
}

mkrepo() { # mkrepo <dir> <branch>
    mkdir -p "$1"
    git -C "$1" init -q --template=
    git -C "$1" symbolic-ref HEAD "refs/heads/$2"
}
mkrepo "$T/on-main" main
mkrepo "$T/on-feat" feat/x
mkrepo "$T/on-contract" contract/render-hook
mkrepo "$T/staged-feat" feat/y
mkrepo "$T/staged-contract" contract/z
mkdir -p "$T/not-a-repo"

FROZEN_REL="integrations/safari/quick-look/Resources/ql-render.js"
ENT_REL="integrations/safari/entitlements/app.entitlements"
OPEN_REL="integrations/safari/quick-look/Resources/boxdraw.js"
for r in staged-feat staged-contract; do
    mkdir -p "$T/$r/$(dirname "$FROZEN_REL")" "$T/$r/$(dirname "$OPEN_REL")"
    echo x >"$T/$r/$FROZEN_REL"
    echo x >"$T/$r/$OPEN_REL"
    echo x >"$T/$r/README.md"
done
git -C "$T/staged-feat" add "$FROZEN_REL"
git -C "$T/staged-contract" add "$FROZEN_REL"
mkrepo "$T/unstaged-feat" feat/u
mkdir -p "$T/unstaged-feat/$(dirname "$FROZEN_REL")"
echo x >"$T/unstaged-feat/$FROZEN_REL"
git -C "$T/unstaged-feat" add "$FROZEN_REL"
git -C "$T/unstaged-feat" -c user.name=t -c user.email=t@t commit -q -m seed
echo y >>"$T/unstaged-feat/$FROZEN_REL"
mkrepo "$T/staged-open" feat/open
mkdir -p "$T/staged-open/$(dirname "$OPEN_REL")"
echo x >"$T/staged-open/$OPEN_REL"
git -C "$T/staged-open" add "$OPEN_REL"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }

run_raw() { # run_raw <json>: sets rc, writes stderr to $T/err
    rc=0
    printf '%s' "$1" | bash "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
}

judge() { # judge <label> <block|allow> [stderr must contain]
    local label="$1" want="$2" needle="${3:-}"
    if [ "$want" = block ]; then
        if [ "$rc" -eq 2 ]; then ok "$label: blocked (exit 2)"; else bad "$label: expected exit 2, got $rc"; fi
        if [ -n "$needle" ]; then
            if grep -Fq -- "$needle" "$T/err"; then ok "$label: message names the fix"; else bad "$label: message lacks '$needle'"; fi
        fi
    else
        if [ "$rc" -eq 0 ]; then ok "$label: allowed (exit 0)"; else bad "$label: expected exit 0, got $rc"; fi
        if [ ! -s "$T/err" ]; then ok "$label: silent"; else bad "$label: printed to stderr"; fi
    fi
}

case_run() { # case_run <label> <block|allow> <cwd> <command> [needle]
    run_raw "$(mkjson Bash "$3" "$4")"
    judge "$1" "$2" "${5:-}"
}

case_edit() { # case_edit <label> <block|allow> <cwd> <path> [needle] [tool]
    run_raw "$(mkjson "${6:-Edit}" "$3" "$4")"
    judge "$1" "$2" "${5:-}"
}

FEAT="$T/on-feat"
MAIN="$T/on-main"
CONTRACT="$T/on-contract"
PUSH_FIX="open a PR from a branch"
FORCE_FIX="merge origin/main into the branch"
VERIFY_FIX="without the flag"
COMMIT_FIX="git switch -c"
FROZEN_FIX="git switch -c contract/<slug>"

# push to main
case_run "push origin main" block "$FEAT" "git push origin main" "$PUSH_FIX"
case_run "push HEAD:main" block "$FEAT" "git push origin HEAD:main" "$PUSH_FIX"
case_run "push refs/heads/main" block "$FEAT" "git push origin feat/x:refs/heads/main" "$PUSH_FIX"
case_run "delete main on the remote" block "$FEAT" "git push origin :main" "$PUSH_FIX"
case_run "git -C <dir> push origin main" block "$T/not-a-repo" "git -C $FEAT push origin main" "$PUSH_FIX"
case_run "bare git push on main" block "$MAIN" "git push" "$PUSH_FIX"
case_run "git push origin on main" block "$MAIN" "git push origin" "$PUSH_FIX"
case_run "push HEAD while on main" block "$MAIN" "git push origin HEAD" "$PUSH_FIX"
case_run "cd <main repo> && git push" block "$T/not-a-repo" "cd $MAIN && git push" "$PUSH_FIX"
case_run "push to main inside bash -c" block "$FEAT" "bash -c \"git push origin main\"" "$PUSH_FIX"
case_run "push to main after env assignment" block "$FEAT" "GIT_SSH_COMMAND=ssh git push origin main" "$PUSH_FIX"
case_run "push feature branch" allow "$FEAT" "git push origin feat/x"
case_run "push -u feature branch" allow "$FEAT" "git push -u origin feat/x"
case_run "bare git push on a feature branch" allow "$FEAT" "git push"
case_run "push dry run to main" allow "$FEAT" "git push --dry-run origin main"
case_run "push main:feature (source is main)" allow "$FEAT" "git push origin main:feat/y"
case_run "push tags from main" allow "$MAIN" "git push --tags"

# force pushes
case_run "push --force" block "$FEAT" "git push --force origin feat/x" "$FORCE_FIX"
case_run "push -f" block "$FEAT" "git push -f origin feat/x" "$FORCE_FIX"
case_run "push -fu" block "$FEAT" "git push -fu origin feat/x" "$FORCE_FIX"
case_run "push --force-with-lease" block "$FEAT" "git push --force-with-lease origin feat/x" "$FORCE_FIX"
case_run "push --force-with-lease=ref" block "$FEAT" "git push --force-with-lease=feat/x origin feat/x" "$FORCE_FIX"
case_run "push --force-if-includes" block "$FEAT" "git push --force-if-includes origin feat/x" "$FORCE_FIX"
case_run "push +branch" block "$FEAT" "git push origin +feat/x" "$FORCE_FIX"
case_run "push +HEAD:branch" block "$FEAT" "git push origin +HEAD:feat/x" "$FORCE_FIX"
case_run "force push inside bash -c" block "$FEAT" "bash -c 'git push --force origin feat/x'" "$FORCE_FIX"
case_run "force push after &&" block "$FEAT" "git fetch origin && git push --force origin feat/x" "$FORCE_FIX"
case_run "force push dry run" allow "$FEAT" "git push --force --dry-run origin feat/x"
case_run "push with a push option named -o" allow "$FEAT" "git push -o ci.skip origin feat/x"

# --no-verify
case_run "commit --no-verify" block "$FEAT" "git commit --no-verify -m x" "$VERIFY_FIX"
case_run "commit -m x --no-verify" block "$FEAT" "git commit -m x --no-verify" "$VERIFY_FIX"
case_run "push --no-verify" block "$FEAT" "git push --no-verify origin feat/x" "$VERIFY_FIX"
case_run "merge --no-verify" block "$FEAT" "git merge --no-verify origin/main" "$VERIFY_FIX"
case_run "commit -n" block "$FEAT" "git commit -n -m x" "$VERIFY_FIX"
case_run "commit -nm" block "$FEAT" "git commit -nm x" "$VERIFY_FIX"
case_run "commit -an" block "$FEAT" "git commit -an" "$VERIFY_FIX"
case_run "git -C <dir> commit --no-verify" block "$T/not-a-repo" "git -C $FEAT commit --no-verify -m x" "$VERIFY_FIX"
case_run "commit message mentions --no-verify" allow "$FEAT" "git commit -m \"docs: never use --no-verify\""
case_run "commit message value is -n" allow "$FEAT" "git commit -m -n"
case_run "commit -am" allow "$FEAT" "git commit -am \"fix: x\""
case_run "commit -F file" allow "$FEAT" "git commit -F msg.txt"
case_run "rg mentions --no-verify" allow "$FEAT" "rg -n -- '--no-verify' docs"
case_run "echo mentions git push --force" allow "$FEAT" "echo \"git push --force is blocked\""
case_run "quoted separator does not split" allow "$FEAT" "echo \"first; git push origin main\""
case_run "rg mentions git push origin main" allow "$FEAT" "rg 'git push origin main' docs"
case_run "git log --grep mentions push" allow "$FEAT" "git log --grep \"git push origin main\""

# commit on main
case_run "commit on main" block "$MAIN" "git commit -m x" "$COMMIT_FIX"
case_run "add and commit with message file on main" block "$MAIN" "git add a && git commit -F msg.txt" "$COMMIT_FIX"
case_run "git -C <main repo> commit" block "$T/not-a-repo" "git -C $MAIN commit -m x" "$COMMIT_FIX"
case_run "commit on a feature branch" allow "$FEAT" "git commit -m \"docs: mention git push origin main\""
case_run "commit message from heredoc names a blocked command" allow "$FEAT" "git commit -F - <<EOF
docs: say git push --force is blocked
git push --force origin x
EOF"
case_run "switch to a branch, then commit, from main" allow "$MAIN" "git switch -c feat/y && git commit -m x"
case_run "commit outside a repo" allow "$T/not-a-repo" "git commit -m x"
case_run "git status on main" allow "$MAIN" "git status"
case_run "plain command" allow "$FEAT" "ls -la"

# frozen files at commit time
case_run "commit with a frozen file staged, feature branch" block "$T/staged-feat" "git commit -m x" "$FROZEN_FIX"
case_run "frozen file staged, contract branch" allow "$T/staged-contract" "git commit -m x"
case_run "non-frozen file staged, feature branch" allow "$T/staged-open" "git commit -m x"
case_run "commit -a with an unstaged frozen change" block "$T/unstaged-feat" "git commit -am x" "$FROZEN_FIX"
case_run "commit with no -a and an unstaged frozen change" allow "$T/unstaged-feat" "git commit -m x"
case_run "commit naming a frozen path" block "$T/staged-open" "git commit -m x -- $FROZEN_REL" "$FROZEN_FIX"
case_run "commit naming a frozen path with ./" block "$T/staged-open" "git commit -m x ./$FROZEN_REL" "$FROZEN_FIX"
case_run "commit naming an entitlements file" block "$T/staged-open" "git commit -m x $ENT_REL" "$FROZEN_FIX"
case_run "commit naming a non-frozen path" allow "$T/staged-open" "git commit -m x $OPEN_REL"

# frozen files at edit time
case_edit "Edit a frozen file, feature branch" block "$T/staged-feat" "$T/staged-feat/$FROZEN_REL" "$FROZEN_FIX"
case_edit "Write a frozen file, feature branch" block "$FEAT" "$FEAT/$FROZEN_REL" "$FROZEN_FIX" Write
case_edit "MultiEdit a frozen file" block "$FEAT" "$FEAT/$FROZEN_REL" "$FROZEN_FIX" MultiEdit
case_edit "NotebookEdit a frozen path" block "$FEAT" "$FEAT/scripts/sd-settings" "$FROZEN_FIX" NotebookEdit
case_edit "Edit with a relative path" block "$FEAT" "tests/smoke.sh" "$FROZEN_FIX"
case_edit "Edit an entitlements file" block "$FEAT" "$FEAT/$ENT_REL" "$FROZEN_FIX"
case_edit "Edit the contract itself" block "$FEAT" "$FEAT/docs/contract-r1.md" "$FROZEN_FIX"
case_edit "Write a new frozen file under a missing directory" block "$FEAT" "$FEAT/integrations/safari/quick-look/Resources/new-dir/../ql-render.js" "$FROZEN_FIX"
case_edit "Edit a frozen file, contract branch" allow "$CONTRACT" "$CONTRACT/$FROZEN_REL"
case_edit "Edit a frozen file, main branch" block "$MAIN" "$MAIN/$FROZEN_REL" "$FROZEN_FIX"
case_edit "Edit a non-frozen file" allow "$FEAT" "$FEAT/$OPEN_REL"
case_edit "Edit a doc" allow "$FEAT" "$FEAT/README.md"
case_edit "Edit a file outside any repo" allow "$T/not-a-repo" "$T/not-a-repo/$FROZEN_REL"
case_edit "Edit a file with the same name elsewhere" allow "$FEAT" "$FEAT/docs/ql-render.js"

# 1. The guard, its list and its wiring are frozen whatever the list says, and the
# list is read as committed on origin/main, not from the working tree.
case_edit "Edit the guard script" block "$FEAT" "$FEAT/scripts/agent-guard.sh" "$FROZEN_FIX"
case_edit "Edit the frozen list" block "$FEAT" "$FEAT/scripts/agent-frozen-paths.txt" "$FROZEN_FIX"
case_edit "Edit the agent settings" block "$FEAT" "$FEAT/.claude/settings.json" "$FROZEN_FIX"
case_edit "Edit the guard script, contract branch" allow "$CONTRACT" "$CONTRACT/scripts/agent-guard.sh"
mkrepo "$T/seed" main
mkdir -p "$T/seed/scripts" "$T/seed/tests"
cp "$LIST" "$T/seed/scripts/agent-frozen-paths.txt"
echo x >"$T/seed/tests/smoke.sh"
echo x >"$T/seed/a.txt"
git -C "$T/seed" add -A
git -C "$T/seed" -c user.name=t -c user.email=t@t commit -q -m seed
git init -q --bare --template= "$T/remote.git"
git -C "$T/seed" push -q "$T/remote.git" main 2>/dev/null
git clone -q --template= "$T/remote.git" "$T/clone" 2>/dev/null
git -C "$T/clone" switch -q -c feat/c
grep -v '^tests/smoke.sh$' "$LIST" >"$T/clone/scripts/agent-frozen-paths.txt"
echo y >>"$T/clone/tests/smoke.sh"
git -C "$T/clone" add tests/smoke.sh
case_edit "list edited in the working tree: frozen file still blocked" block "$T/clone" "$T/clone/tests/smoke.sh" "$FROZEN_FIX"
case_run "list edited in the working tree: commit still blocked" block "$T/clone" "git commit -m x" "$FROZEN_FIX"
case_edit "list edited in the working tree: the list itself is blocked" block "$T/clone" "$T/clone/scripts/agent-frozen-paths.txt" "$FROZEN_FIX"
git -C "$T/clone" reset -q
mkdir -p "$T/clone/.claude"
echo '{}' >"$T/clone/.claude/settings.json"
git -C "$T/clone" add .claude/settings.json
case_run "settings.json staged: commit blocked" block "$T/clone" "git commit -m x" "$FROZEN_FIX"

# 2. git accepts any unambiguous prefix of a long option
case_run "push --forc" block "$FEAT" "git push --forc origin feat/x" "$FORCE_FIX"
case_run "push --force-w" block "$FEAT" "git push --force-w origin feat/x" "$FORCE_FIX"
case_run "push --force-if" block "$FEAT" "git push --force-if origin feat/x" "$FORCE_FIX"
case_run "push --force-with-lease abbreviated with a value" block "$FEAT" "git push --force-with origin feat/x" "$FORCE_FIX"
case_run "push --mirror" block "$FEAT" "git push --mirror origin" "overwrites every ref"
case_run "push --mirr" block "$FEAT" "git push --mirr origin" "overwrites every ref"
case_run "commit --no-ver" block "$FEAT" "git commit --no-ver -m x" "$VERIFY_FIX"
case_run "commit --no-v" block "$FEAT" "git commit --no-v -m x" "$VERIFY_FIX"
case_run "push --no-veri" block "$FEAT" "git push --no-veri origin feat/x" "$VERIFY_FIX"
case_run "merge --no-verif" block "$FEAT" "git merge --no-verif origin/main" "$VERIFY_FIX"
case_run "push --follow-tags" allow "$FEAT" "git push --follow-tags origin feat/x"
case_run "commit --no-edit" allow "$FEAT" "git commit --no-edit"
case_run "commit --no-gpg-sign" allow "$FEAT" "git commit --no-gpg-sign -m x"
case_run "push --set-upstream" allow "$FEAT" "git push --set-upstream origin feat/x"

# 3. hook switches in config, and git env in front of git
HOOKS_FIX="leave core.hooksPath alone"
ENV_FIX="run git without them"
case_run "-c core.hooksPath" block "$FEAT" "git -c core.hooksPath=/dev/null commit -m x" "$HOOKS_FIX"
case_run "-c core.hookspath (lower case)" block "$FEAT" "git -c core.hookspath=/x push origin feat/x" "$HOOKS_FIX"
case_run "-ccore.hooksPath attached" block "$FEAT" "git -ccore.hooksPath=/x commit -m x" "$HOOKS_FIX"
case_run "--config-env=core.hooksPath" block "$FEAT" "git --config-env=core.hooksPath=HP commit -m x" "$HOOKS_FIX"
case_run "--config-env core.hooksPath" block "$FEAT" "git --config-env core.hooksPath=HP commit -m x" "$HOOKS_FIX"
case_run "git config core.hooksPath" block "$FEAT" "git config core.hooksPath /dev/null" "$HOOKS_FIX"
case_run "git config --local core.hooksPath" block "$FEAT" "git config --local core.hooksPath /dev/null" "$HOOKS_FIX"
case_run "GIT_CONFIG_COUNT in front of git" block "$FEAT" "GIT_CONFIG_COUNT=1 git commit -m x" "$ENV_FIX"
case_run "GIT_CONFIG_KEY_0 in front of git" block "$FEAT" "GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x git push origin feat/x" "$ENV_FIX"
case_run "GIT_CONFIG_GLOBAL in front of git" block "$FEAT" "GIT_CONFIG_GLOBAL=/x git commit -m x" "$ENV_FIX"
case_run "GIT_DIR in front of git" block "$FEAT" "GIT_DIR=/x/.git git status" "$ENV_FIX"
case_run "env GIT_DIR git" block "$FEAT" "env GIT_DIR=/x/.git git status" "$ENV_FIX"
case_run "export GIT_CONFIG_PARAMETERS" block "$FEAT" "export GIT_CONFIG_PARAMETERS=x; git commit -m y" "$ENV_FIX"
case_run "git -c user.name is fine" allow "$FEAT" "git -c user.name=x commit -m y"
case_run "git -c color.ui is fine" allow "$FEAT" "git -c color.ui=never status"
case_run "GIT_AUTHOR_NAME in front of git is fine" allow "$FEAT" "GIT_AUTHOR_NAME=x git commit -m y"
case_run "git config user.name is fine" allow "$FEAT" "git config user.name x"

# 4. a switch earlier in the command counts only when it can have worked
mkrepo "$T/multi" main
echo x >"$T/multi/a.txt"
git -C "$T/multi" add a.txt
git -C "$T/multi" -c user.name=t -c user.email=t@t commit -q -m seed
git -C "$T/multi" branch feat/ok
M="$T/multi"
case_run "switch -c then commit, from main" allow "$M" "git switch -c feat/new && git commit -m x"
case_run "checkout -b then commit, from main" allow "$M" "git checkout -b feat/new && git commit -m x"
case_run "switch to an existing branch then commit" allow "$M" "git switch feat/ok && git commit -m x"
case_run "switch to a missing branch then commit" block "$M" "git switch feat/missing && git commit -m x" "$COMMIT_FIX"
case_run "path checkout does not change the branch" block "$M" "git checkout feat/ok -- a.txt && git commit -m x" "$COMMIT_FIX"
case_run "path checkout after -- does not change the branch" block "$M" "git checkout -- feat/ok && git commit -m x" "$COMMIT_FIX"
case_run "a plain checkout is not trusted" block "$M" "git checkout feat/ok && git commit -m x" "$COMMIT_FIX"
case_run "switch -c main then commit" block "$M" "git switch -C main && git commit -m x" "$COMMIT_FIX"
case_run "switch to main then commit" block "$M" "git switch main && git commit -m x" "$COMMIT_FIX"
case_run "a failed switch does not hide main" block "$M" "git switch feat/missing; git commit -m x" "$COMMIT_FIX"

# 5. push destinations that mean main
mkrepo "$T/prev" main
echo x >"$T/prev/a.txt"
git -C "$T/prev" add a.txt
git -C "$T/prev" -c user.name=t -c user.email=t@t commit -q -m seed
git -C "$T/prev" branch feat/ok
git -C "$T/prev" switch -q feat/ok
git -C "$T/prev" switch -q main
git -C "$T/prev" switch -q feat/ok
case_run "push @ while on main" block "$M" "git push origin @" "$PUSH_FIX"
case_run "push HEAD:@ while on main" block "$M" "git push origin HEAD:@" "$PUSH_FIX"
case_run "push HEAD:@{-1}, which is main" block "$T/prev" "git push origin HEAD:@{-1}" "$PUSH_FIX"
case_run "push HEAD:heads/main" block "$FEAT" "git push origin HEAD:heads/main" "$PUSH_FIX"
case_run "push @ while on a feature branch" allow "$T/prev" "git push origin @"
case_run "push HEAD:feat/ok from a feature branch" allow "$T/prev" "git push origin HEAD:feat/ok"

# Bad input never traps a session.
run_raw '{not json'
if [ "$rc" -eq 0 ]; then ok "malformed JSON: allowed (exit 0)"; else bad "malformed JSON: expected exit 0, got $rc"; fi
run_raw ''
if [ "$rc" -eq 0 ]; then ok "empty input: allowed (exit 0)"; else bad "empty input: expected exit 0, got $rc"; fi
run_raw '{"tool_name":"Bash","tool_input":{}}'
if [ "$rc" -eq 0 ]; then ok "no command field: allowed (exit 0)"; else bad "no command field: expected exit 0, got $rc"; fi

# Parser fallbacks: a PATH with only the tools the guard and git need.
mkbin() { # mkbin <dir> <tool>...
    local d="$1" t p
    shift
    mkdir -p "$d"
    for t in "$@"; do
        p="$(command -v "$t" 2>/dev/null || true)"
        [ -z "$p" ] || ln -sf "$p" "$d/$t"
    done
}
BLOCK_JSON="$(mkjson Bash "$FEAT" "git push origin main")"
mkbin "$T/bin-py" bash cat awk tr sed git dirname basename env python3
if PATH="$T/bin-py" python3 -c 'import json' >/dev/null 2>&1; then
    rc=0
    printf '%s' "$BLOCK_JSON" | PATH="$T/bin-py" bash "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
    if [ "$rc" -eq 2 ] && grep -Fq "$PUSH_FIX" "$T/err"; then ok "python3 only: blocks and names the fix"; else bad "python3 only: rc $rc"; fi
    EDIT_JSON="$(mkjson Edit "$FEAT" "$FEAT/$FROZEN_REL")"
    rc=0
    printf '%s' "$EDIT_JSON" | PATH="$T/bin-py" bash "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
    if [ "$rc" -eq 2 ] && grep -Fq "$FROZEN_FIX" "$T/err"; then ok "python3 only: blocks a frozen edit"; else bad "python3 only frozen edit: rc $rc"; fi
else
    echo "skip  python3 does not run from a bare PATH here"
fi

mkbin "$T/bin-none" bash cat awk tr sed git dirname basename env
rc=0
printf '%s' "$BLOCK_JSON" | PATH="$T/bin-none" bash "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 0 ] && grep -Fq "neither jq nor python3" "$T/err"; then ok "no parser: allowed with a note"; else bad "no parser: rc $rc"; fi

# The frozen list agrees with the contract.
total=0
while IFS= read -r pat; do
    case "$pat" in "" | "#"*) continue ;; esac
    total=$((total + 1))
    n="$(git ls-files -- "$pat" | wc -l | tr -d ' ')"
    if [ "$n" -gt 0 ]; then ok "frozen list: '$pat' matches $n tracked file(s)"; else bad "frozen list: '$pat' matches no tracked file (renamed or removed?)"; fi
    if [ "$pat" != "docs/contract-r1.md" ]; then
        if grep -Fq -- "$(basename "$pat")" docs/contract-r1.md; then ok "frozen list: the contract names '$(basename "$pat")'"; else bad "frozen list: the contract does not name '$(basename "$pat")'"; fi
    fi
done <"$LIST"
[ "$total" -gt 0 ] || bad "frozen list is empty"

line="$(awk '/^### Shared and frozen/ {f=1; next} f && NF {print; exit}' docs/contract-r1.md)"
line="${line%%(except*}"
tokens="$(printf '%s\n' "$line" | grep -o '`[^`]*`' | tr -d '`')"
[ -n "$tokens" ] || bad "could not read the frozen paragraph of docs/contract-r1.md"
while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if grep -Fq -- "$tok" "$LIST"; then ok "contract: frozen '$tok' is in the list"; else bad "contract: frozen '$tok' is missing from scripts/agent-frozen-paths.txt"; fi
done <<EOF
$tokens
EOF

echo "failures: $fails"
[ "$fails" -eq 0 ]
