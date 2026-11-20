#!/usr/bin/env bash
# agent-guard.sh - Claude Code PreToolUse hook: a best-effort seatbelt against agent
# accidents, not a security boundary. It refuses, with the fix in the message:
#   1. a push to main (also @, HEAD or @{-1} while main is checked out)
#   2. a force push (-f, --force*, +ref) and --mirror
#   3. --no-verify, `git commit -n`, setting core.hooksPath, and a commit on main
#   4. an edit or commit of a file docs/contract-r1.md freezes, off a contract/<slug>
#      branch. The list is scripts/agent-frozen-paths.txt as committed on
#      refs/remotes/origin/main; this script, that list and .claude/settings.json are
#      always frozen.
# Wired in .claude/settings.json for Bash (1 to 4) and Edit, Write, MultiEdit,
# NotebookEdit (4). Exit 2 blocks and shows stderr to the agent; anything else allows,
# so a broken guard never traps a session. Without jq it fails closed (exit 2).
#
# Known gaps. It reads command text, with quote characters removed and a quoted string
# that holds a space folded to one word, and judges only commands whose first word is
# git. A determined agent gets past it: bash -c or eval, a script or variable that runs
# git, crafted quoting that hides arguments (the quote fold can span two quote pairs),
# config includes (include.path, includeIf), GIT_CONFIG_* or GIT_DIR set in front
# of git or exported, a sed -i on a frozen file (the commit-time check still catches
# it). A switch earlier in the same command is not followed, so the guard sees the
# branch you are on now: switch in one call, commit in the next. It guards Claude Code
# only. The real control is the server-side ruleset on main: a required PR, required
# checks, no force push. Review is the second line.
set -f
ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
command -v jq >/dev/null 2>&1 || { echo "agent-guard needs jq; macOS 15+ ships /usr/bin/jq, or brew install jq" >&2; exit 2; }
input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
cwd="$(field '.cwd // ""')"
fpath="$(field '.tool_input.file_path // .tool_input.notebook_path // ""')"
cmd="$(field '.tool_input.command // ""')"
[ -n "$cmd$fpath" ] || exit 0
base="${cwd:-$PWD}"
block() { printf 'agent-guard: %s\nFix: %s\n' "$1" "$2" >&2; exit 2; }

# The built-in paths, then the list as committed on origin/main (the working tree copy
# only when the repo has no origin/main, as in a fresh repo or a test).
frozen_patterns() { # <repo top>
    printf '%s\n' scripts/agent-guard.sh scripts/agent-frozen-paths.txt .claude/settings.json
    if git -C "$1" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then
        git -C "$1" show refs/remotes/origin/main:scripts/agent-frozen-paths.txt 2>/dev/null
    else
        cat "$1/scripts/agent-frozen-paths.txt" 2>/dev/null || cat "$ROOT/scripts/agent-frozen-paths.txt" 2>/dev/null
    fi
    return 0
}
is_frozen() { # <repo-relative path> <patterns>; "x/../" parts are folded so ../ cannot dodge
    local IFS=/ part pat rel
    local -a out=()
    for part in $1; do
        case "$part" in "" | .) ;; ..) [ "${#out[@]}" -eq 0 ] || out=("${out[@]:0:${#out[@]}-1}") ;; *) out+=("$part") ;; esac
    done
    rel="${out[*]-}"
    IFS=$'\n'
    for pat in $2; do
        # shellcheck disable=SC2254
        case "$pat" in "" | "#"*) ;; *) case "$rel" in $pat) return 0 ;; esac ;; esac
    done
    return 1
}
frozen_block() { # <path> <dir>: blocked unless the branch is contract/<slug>
    case "$(git -C "$2" symbolic-ref --short -q HEAD 2>/dev/null)" in contract/?*) return 0 ;; esac
    block "$1 is frozen by docs/contract-r1.md: a change goes through its own contract PR, never inside a feature PR." \
        "git switch -c contract/<slug>; change only the frozen file there; open the PR and say why in its body (AGENTS.md, 'The release contract')"
}

if [ -n "$fpath" ]; then # Edit, Write, MultiEdit, NotebookEdit
    case "$fpath" in /*) ;; *) fpath="$base/$fpath" ;; esac
    d="$fpath" tail=""
    while [ ! -d "$d" ]; do tail="/$(basename "$d")$tail"; d="$(dirname "$d")"; done
    d="$(cd "$d" 2>/dev/null && pwd -P)" || exit 0
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || exit 0
    rel="${d#"$top"}$tail"
    is_frozen "${rel#/}" "$(frozen_patterns "$top")" && frozen_block "${rel#/}" "$d"
    exit 0
fi

long_opt() { # <word> <name> [min]: --<name> or a git abbreviation of it (4+ characters)
    local n="${1#--}"
    case "$1" in --?*) ;; *) return 1 ;; esac
    n="${n%%=*}"
    [ "${#n}" -ge "${3:-4}" ] && [ "${2#"$n"}" != "$2" ]
}
cfg_check() { # a name=value that moves the hooks directory switches the repo's hooks off
    case "$(printf '%s' "${1%%=*}" | tr '[:upper:]' '[:lower:]')" in
    core.hookspath) block "setting core.hooksPath switches the repo's hooks and checks off." "leave core.hooksPath alone; fix what the check reports" ;;
    esac
}
commit_check() { # <dir> <words>
    local dir="$1" all=0 a f top pats prefix
    local -a paths=()
    shift
    for a in "$@"; do
        case "$a" in
        --all) all=1 ;;
        --*) ;;
        -?*)
            case "$a" in *n*) block "git commit -n is --no-verify: it skips the repo's hooks and checks." "fix what the check reports, then commit again without the flag" ;; esac
            case "$a" in *a*) all=1 ;; esac
            ;;
        *) paths+=("$a") ;;
        esac
    done
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
    [ "$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)" = "main" ] &&
        block "you are on main, and nothing commits to main directly." "git switch -c <type>/<slug>   (your changes come with you), then commit again"
    pats="$(frozen_patterns "$top")"
    prefix="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)"
    for f in $(git -C "$dir" diff --cached --name-only 2>/dev/null) $([ "$all" -eq 1 ] && git -C "$dir" diff --name-only 2>/dev/null) "${paths[@]+"${paths[@]/#/$prefix}"}"; do
        is_frozen "$f" "$pats" && frozen_block "$f" "$dir"
    done
    return 0
}
push_check() { # <dir> <words>
    local dir="$1" a force=0 skip=0 dry=0 tags=0 remote="" r dst full cur
    local -a refs=()
    local msg="a push to main skips review: nothing lands on main except through a PR."
    local fix="git switch -c <type>/<slug>; git push -u origin <type>/<slug>; gh pr create"
    local fmsg="a force push rewrites history that others may have pulled."
    local ffix="push a new commit, or merge origin/main into the branch; a maintainer force-pushes by hand when it is truly needed"
    shift
    for a in "$@"; do
        [ "$skip" -eq 1 ] && { skip=0; continue; }
        long_opt "$a" mirror 1 && block "git push --mirror overwrites every ref on the remote, main included." "push the one branch you mean: git push -u origin <type>/<slug>"
        if long_opt "$a" force || long_opt "$a" force-with-lease || long_opt "$a" force-if-includes; then force=1; continue; fi
        case "$a" in
        -n | --dry-run) dry=1 ;;
        --tags) tags=1 ;;
        -o | --push-option | --repo) skip=1 ;;
        --*) ;;
        -?*) case "$a" in *f*) force=1 ;; esac ;;
        *) if [ -z "$remote" ]; then remote="$a"; else refs+=("$a"); fi ;;
        esac
    done
    [ "$dry" -eq 0 ] || return 0
    [ "$force" -eq 0 ] || block "$fmsg" "$ffix"
    cur="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)"
    [ "${#refs[@]}" -gt 0 ] || { [ "$tags" -eq 0 ] && [ "$cur" = "main" ] && block "$msg" "$fix"; return 0; }
    for r in "${refs[@]}"; do
        case "$r" in +*) block "$fmsg" "$ffix" ;; esac
        dst="${r#*:}"
        dst="${dst#refs/heads/}"
        dst="${dst#heads/}"
        case "$dst" in "" | -*) continue ;; main) block "$msg" "$fix" ;; HEAD | @) dst="$cur" ;; esac
        full="$(git -C "$dir" rev-parse --symbolic-full-name "$dst" 2>/dev/null)"
        [ "$dst" = "main" ] || [ "$full" = "refs/heads/main" ] && block "$msg" "$fix"
    done
    return 0
}

# Judge each command whose first word is git, after the quoted strings are dropped.
while IFS= read -r seg; do
    # shellcheck disable=SC2086
    set -- $seg
    while [ $# -gt 0 ]; do case "$1" in [A-Za-z_]*=* | sudo | command | exec | env) shift ;; *) break ;; esac; done
    [ "${1-}" = "git" ] || continue
    shift
    dir="$base"
    while [ $# -gt 0 ]; do
        case "$1" in
        -C) case "${2-.}" in /*) dir="${2-.}" ;; *) dir="$dir/${2-.}" ;; esac; shift; [ $# -gt 0 ] && shift ;;
        -c | --config-env) cfg_check "${2-}"; shift; [ $# -gt 0 ] && shift ;;
        -c?*) cfg_check "${1#-c}"; shift ;;
        --config-env=*) cfg_check "${1#*=}"; shift ;;
        -*) shift ;;
        *) break ;;
        esac
    done
    sub="${1-}"
    [ $# -gt 0 ] && shift
    for a in "$@"; do long_opt "$a" no-verify && block "--no-verify skips the repo's hooks and checks." "fix what the check reports, then run the command again without the flag"; done
    case "$sub" in
    config) for a in "$@"; do cfg_check "$a"; done ;;
    commit) commit_check "$dir" "$@" ;;
    push) push_check "$dir" "$@" ;;
    esac
done <<EOF
$(printf '%s' "$cmd" | sed -E "s/\"[^\"]*[[:space:]][^\"]*\"/Q/g; s/'[^']*[[:space:]][^']*'/Q/g; s/[\"']//g" | tr ';&|' '\n\n\n')
EOF
exit 0
