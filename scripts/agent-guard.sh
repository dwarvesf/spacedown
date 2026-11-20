#!/usr/bin/env bash
# agent-guard.sh - Claude Code PreToolUse hook. It stops five wrong actions at the
# moment they happen and says what to do instead.
#
#   1. `git push` that targets main              -> push a branch and open a PR
#   2. a force push (-f, --force*, +ref)         -> push a new commit, or merge main in
#   3. --no-verify, or `git commit -n`           -> fix what the check reports
#   4. `git commit` while on main                -> create a branch first
#   5. an edit or a commit that touches a file docs/contract-r1.md freezes
#      (the list is scripts/agent-frozen-paths.txt), on a branch that is not
#      named contract/<slug>                     -> use a contract branch and PR
#
# Wired in .claude/settings.json for the Bash tool (rules 1 to 5, the commit-time
# check for 5) and for Edit, Write, MultiEdit and NotebookEdit (rule 5 at edit
# time). Claude Code sends the hook JSON on stdin (cwd, tool_input.command or
# tool_input.file_path) and treats exit 2 as "block", with stderr shown to the
# agent. Exit 0 allows. Any other failure also allows, so a broken guard never
# traps a session.
#
# JSON is read with jq when present, else python3, else the call is allowed with
# a one-line note on stderr. No network, and no git call unless the command
# contains `git`. There is no bypass variable: a bypass the agent can set is not
# a guard.
#
# Limits: this is text matching on the command line, not a shell parser. It splits
# on && || ; | and newlines outside quotes, skips heredoc bodies, and judges the
# first word of each part, so `echo "git push origin main"` and `rg 'git push'`
# pass. It also looks inside `bash -c` and `eval`. It cannot see a command built
# from variables, a script that runs git itself, or a `sed -i` on a frozen file
# (the commit-time check still catches that one). It guards Claude Code only.
# Review and CI are the second line.
set -o pipefail

GUARD_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

input="$(cat)"

# Four lines: cwd, tool name, file path, then the command (which may span lines).
# The trailing x keeps $( ) from eating a final empty line.
parsed=""
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -e . >/dev/null 2>&1 || {
        echo "agent-guard: could not read the hook input, allowing" >&2
        exit 0
    }
    parsed="$(printf '%s' "$input" | jq -r '(.cwd // ""), (.tool_name // ""), ((.tool_input.file_path // .tool_input.notebook_path // "") | gsub("\n"; " ")), (.tool_input.command // "")' 2>/dev/null; printf x)"
elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 || {
        echo "agent-guard: could not read the hook input, allowing" >&2
        exit 0
    }
    parsed="$(printf '%s' "$input" | python3 -c 'import json,sys
d = json.load(sys.stdin)
t = d.get("tool_input") or {}
print(d.get("cwd") or "")
print(d.get("tool_name") or "")
print((t.get("file_path") or t.get("notebook_path") or "").replace("\n", " "))
print(t.get("command") or "")' 2>/dev/null; printf x)"
else
    echo "agent-guard: neither jq nor python3 is installed, so the guard is off" >&2
    exit 0
fi
parsed="${parsed%x}"

cwd="" fpath="" cmd=""
case "$parsed" in
*"
"*"
"*"
"*)
    cwd="${parsed%%
*}"
    parsed="${parsed#*
}"
    parsed="${parsed#*
}"
    fpath="${parsed%%
*}"
    cmd="${parsed#*
}"
    ;;
esac
[ -n "$cmd$fpath" ] || exit 0

eff_dir="${cwd:-$PWD}"
branch_override=""
depth=0

block() { # block <rule> <fix>
    printf 'agent-guard: %s\nFix: %s\n' "$1" "$2" >&2
    exit 2
}

# ---- the frozen files ------------------------------------------------------

# frozen_list <repo top>: the pattern file of that repo, else this guard's own
frozen_list() {
    if [ -f "$1/scripts/agent-frozen-paths.txt" ]; then
        printf '%s' "$1/scripts/agent-frozen-paths.txt"
    else
        printf '%s' "$GUARD_ROOT/scripts/agent-frozen-paths.txt"
    fi
}

# norm_rel <path>: drop "", "." and "x/.." parts so a ../ cannot dodge a pattern
norm_rel() {
    local IFS=/ part
    local -a out=()
    for part in $1; do
        case "$part" in
        "" | .) ;;
        ..)
            if [ "${#out[@]}" -gt 0 ]; then out=("${out[@]:0:${#out[@]}-1}"); fi
            ;;
        *) out+=("$part") ;;
        esac
    done
    printf '%s' "${out[*]-}"
}

# is_frozen <repo-relative path> <list file>: 0 when a pattern matches
is_frozen() {
    local rel pat
    [ -f "$2" ] || return 1
    rel="$(norm_rel "$1")"
    while IFS= read -r pat || [ -n "$pat" ]; do
        case "$pat" in "" | "#"*) continue ;; esac
        # shellcheck disable=SC2254
        case "$rel" in $pat) return 0 ;; esac
    done <"$2"
    return 1
}

frozen_block() { # frozen_block <path>
    block "$1 is frozen by docs/contract-r1.md. A change to it goes through its own contract PR, never inside a feature PR." \
        "git switch -c contract/<slug>; change only the frozen file there; open the PR and say why in its body (AGENTS.md, 'The release contract'). A maintainer decides."
}

contract_branch() { # contract_branch <branch>: 0 for contract/<slug>
    case "$1" in contract/?*) return 0 ;; esac
    return 1
}

# edit_check <path>: the Edit, Write, MultiEdit and NotebookEdit tools
edit_check() {
    local p="$1" d tail="" top full rel b
    case "$p" in /*) ;; *) p="$eff_dir/$p" ;; esac
    d="$p"
    while [ ! -d "$d" ]; do
        tail="/$(basename "$d")$tail"
        d="$(dirname "$d")"
    done
    d="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 0
    top="$(cd "$top" 2>/dev/null && pwd -P)" || return 0
    full="$d$tail"
    rel="${full#"$top"/}"
    [ "$rel" != "$full" ] || return 0
    is_frozen "$rel" "$(frozen_list "$top")" || return 0
    b="$(git -C "$d" symbolic-ref --short -q HEAD 2>/dev/null || true)"
    contract_branch "$b" || frozen_block "$rel"
    return 0
}

# ---- the command line ------------------------------------------------------

# One part per line; separators inside quotes become control characters, so a
# quoted `;` or `&&` does not split. Heredoc bodies are dropped.
split_parts() {
    awk '
    BEGIN { inq = ""; hd = "" }
    function flush() { if (seg ~ /[^ \t]/) print seg; seg = "" }
    {
        if (hd != "") {
            t = $0
            gsub(/^[ \t]+|[ \t]+$/, "", t)
            if (t == hd) hd = ""
            next
        }
        line = $0
        n = length(line)
        pending = ""
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (inq != "") {
                if (c == inq) { inq = ""; seg = seg c }
                else if (inq == "\"" && c == "\\") { seg = seg c substr(line, i + 1, 1); i++ }
                else if (c == ";") seg = seg "\001"
                else if (c == "&") seg = seg "\002"
                else if (c == "|") seg = seg "\003"
                else seg = seg c
                continue
            }
            if (c == "\\") { seg = seg c substr(line, i + 1, 1); i++; continue }
            if (c == "\"" || c == "\047") { inq = c; seg = seg c; continue }
            if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) break
            if (c == ";" || c == "&" || c == "|") { flush(); continue }
            if (c == "<" && substr(line, i, 2) == "<<" && substr(line, i, 3) != "<<<") {
                j = i + 2
                if (substr(line, j, 1) == "-") j++
                while (substr(line, j, 1) == " ") j++
                q = substr(line, j, 1)
                if (q == "\"" || q == "\047") j++
                w = ""
                while (j <= n && substr(line, j, 1) ~ /[A-Za-z0-9_]/) { w = w substr(line, j, 1); j++ }
                if (w != "") pending = w
                seg = seg "<<"
                i++
                continue
            }
            seg = seg c
        }
        if (inq != "") seg = seg "\004"
        else flush()
        if (pending != "") hd = pending
    }
    END { flush() }'
}

branch_of() { # branch_of <dir>
    if [ -n "$branch_override" ]; then
        printf '%s' "$branch_override"
        return
    fi
    git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || true
}

resolve_dir() { # resolve_dir <path>: relative to the current effective dir
    local d="$1"
    case "$d" in
    "~"*) d="$HOME${d#\~}" ;;
    esac
    case "$d" in
    /*) printf '%s' "$d" ;;
    *) printf '%s/%s' "$eff_dir" "$d" ;;
    esac
}

# frozen_commit_check <dir> <all-flag> <path words...>: what a commit would record
frozen_commit_check() {
    local dir="$1" all="$2" top list b f prefix w
    shift 2
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
    list="$(frozen_list "$top")"
    b="$(branch_of "$dir")"
    contract_branch "$b" && return 0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if is_frozen "$f" "$list"; then frozen_block "$f"; fi
    done <<EOF
$(git -C "$dir" diff --cached --name-only 2>/dev/null)
$([ "$all" -eq 1 ] && git -C "$dir" diff --name-only 2>/dev/null)
EOF
    prefix="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null || true)"
    for w in "$@"; do
        if is_frozen "$prefix${w#./}" "$list"; then frozen_block "$prefix${w#./}"; fi
    done
    return 0
}

check_git() { # check_git <words...>, the words after `git`
    local dir="$eff_dir" sub="" i=0
    local -a w=()
    w=("$@")
    while [ "$i" -lt "${#w[@]}" ]; do
        case "${w[$i]}" in
        -C)
            dir="$(resolve_dir "${w[$((i + 1))]:-.}")"
            i=$((i + 2))
            ;;
        -c)
            i=$((i + 2))
            ;;
        -*) i=$((i + 1)) ;;
        *)
            sub="${w[$i]}"
            i=$((i + 1))
            break
            ;;
        esac
    done
    local -a rest=()
    rest=("${w[@]:$i}")

    # --no-verify on any git command, and `git commit -n`
    local a
    for a in "${rest[@]+"${rest[@]}"}"; do
        case "$a" in
        --no-verify)
            block "--no-verify skips the repo's hooks and checks." \
                "fix what the check reports, then run the command again without the flag"
            ;;
        esac
    done

    case "$sub" in
    switch | checkout)
        # A branch change earlier in the same command decides the later parts.
        local target="" prev=""
        for a in "${rest[@]+"${rest[@]}"}"; do
            case "$prev" in
            -c | -b | -B | -C | --create)
                target="$a"
                break
                ;;
            esac
            case "$a" in
            -*) ;;
            *) [ -n "$target" ] || target="$a" ;;
            esac
            prev="$a"
        done
        [ -z "$target" ] || branch_override="$target"
        ;;
    commit)
        local skip=0 all=0 last paths_done=0
        local -a pathwords=()
        for a in "${rest[@]+"${rest[@]}"}"; do
            if [ "$skip" -eq 1 ]; then
                skip=0
                continue
            fi
            if [ "$paths_done" -eq 1 ]; then
                pathwords+=("$a")
                continue
            fi
            case "$a" in
            --) paths_done=1 ;;
            --all) all=1 ;;
            --message | --file | --author | --date | --template | --reuse-message | --reedit-message | --cleanup | --fixup | --squash | --trailer) skip=1 ;;
            --*) ;;
            -[A-Za-z]*)
                last="${a#"${a%?}"}"
                case "$a" in
                *n*) block "git commit -n is --no-verify: it skips the repo's hooks and checks." \
                    "fix what the check reports, then run the command again without the flag" ;;
                esac
                case "$a" in *a*) all=1 ;; esac
                case "$last" in m | F | C | c | t) skip=1 ;; esac
                ;;
            *) pathwords+=("$a") ;;
            esac
        done
        local b
        b="$(branch_of "$dir")"
        if [ "$b" = "main" ]; then
            block "you are on main, and nothing commits to main directly." \
                "git switch -c <type>/<slug>   (your changes come with you), then commit again"
        fi
        frozen_commit_check "$dir" "$all" "${pathwords[@]+"${pathwords[@]}"}"
        ;;
    push)
        local skip=0 dry=0 tags=0 remote_seen=0 force=0
        local -a refs=()
        for a in "${rest[@]+"${rest[@]}"}"; do
            if [ "$skip" -eq 1 ]; then
                skip=0
                continue
            fi
            case "$a" in
            -n | --dry-run) dry=1 ;;
            --tags) tags=1 ;;
            -f | --force | --force-with-lease | --force-with-lease=* | --force-if-includes) force=1 ;;
            -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
            -[A-Za-z]*)
                case "$a" in *f*) force=1 ;; esac
                ;;
            -*) ;;
            *)
                if [ "$remote_seen" -eq 0 ]; then
                    remote_seen=1
                else
                    refs+=("$a")
                fi
                ;;
            esac
        done
        [ "$dry" -eq 0 ] || return 0
        local b
        b="$(branch_of "$dir")"
        local msg="a push to main skips review, and nothing lands on main except through a PR."
        local fix="git switch -c <type>/<slug>; git push -u origin <type>/<slug>; gh pr create   (open a PR from a branch)"
        local fmsg="a force push rewrites history that others may have pulled."
        local ffix="push a new commit, or merge origin/main into the branch; a maintainer force-pushes by hand when it is truly needed"
        [ "$force" -eq 0 ] || block "$fmsg" "$ffix"
        if [ "${#refs[@]}" -eq 0 ]; then
            if [ "$tags" -eq 0 ] && [ "$b" = "main" ]; then block "$msg" "$fix"; fi
            return 0
        fi
        local r dst
        for r in "${refs[@]}"; do
            case "$r" in
            +*) block "$fmsg" "$ffix" ;;
            esac
            case "$r" in
            *:*) dst="${r#*:}" ;;
            *) dst="$r" ;;
            esac
            dst="${dst#refs/heads/}"
            if [ "$dst" = "main" ]; then block "$msg" "$fix"; fi
            if [ "$dst" = "HEAD" ] && [ "$b" = "main" ]; then block "$msg" "$fix"; fi
        done
        ;;
    esac
    return 0
}

# parse_seg <part>: sets P_first (the command word, after sudo, VAR=x and the
# like) and P_args (the words after it); P_first is empty when there is none
P_first=""
P_args=()
parse_seg() {
    local seg="$1" word i=0 n
    local -a w=() c=()
    P_first=""
    P_args=()
    # shellcheck disable=SC2162
    read -a w <<<"$seg" || true
    n="${#w[@]}"
    for ((i = 0; i < n; i++)); do
        word="${w[$i]//\"/}"
        c+=("${word//\'/}")
    done
    i=0
    while [ "$i" -lt "$n" ]; do
        word="${c[$i]#(}"
        case "$word" in
        "" | sudo | env | command | exec | nohup | time | if | then | else | do | while | until | '!' | '{') i=$((i + 1)) ;;
        [A-Za-z_]*=*) i=$((i + 1)) ;;
        *) break ;;
        esac
    done
    [ "$i" -lt "$n" ] || return 0
    P_first="${c[$i]#(}"
    P_first="${P_first##*/}"
    P_args=("${c[@]:$((i + 1))}")
}

# A quoted string with a space in it is one message, not a list of options: fold it
# to one word, so `git commit -m "never use --no-verify"` is not read as a flag.
fold_quotes() {
    printf '%s' "$1" | sed -E "s/\"[^\"]*[[:space:]][^\"]*\"/Q/g; s/'[^']*[[:space:]][^']*'/Q/g"
}

check_segment() { # check_segment <one part>
    local seg="$1"
    parse_seg "$seg"
    local first="$P_first"
    [ -n "$first" ] || return 0
    local -a args=()
    args=("${P_args[@]+"${P_args[@]}"}")

    case "$first" in
    cd | pushd)
        case "${args[0]:-}" in
        "" | - | *'$'*) ;;
        *) eff_dir="$(resolve_dir "${args[0]}")" ;;
        esac
        ;;
    git)
        parse_seg "$(fold_quotes "$seg")"
        check_git "${P_args[@]+"${P_args[@]}"}"
        ;;
    bash | sh | zsh | dash | ksh | eval)
        [ "$depth" -lt 3 ] || return 0
        local k=0 m="${#args[@]}" found=0
        if [ "$first" = "eval" ]; then
            found=1
        else
            while [ "$k" -lt "$m" ]; do
                case "${args[$k]}" in
                -c | -[a-z]*c)
                    found=1
                    k=$((k + 1))
                    break
                    ;;
                esac
                k=$((k + 1))
            done
        fi
        if [ "$found" -eq 1 ]; then
            local payload="${args[*]:$k}"
            payload="$(printf '%s' "$payload" | tr '\001\002\003\004' ';&|\n')"
            depth=$((depth + 1))
            check_command "$payload"
            depth=$((depth - 1))
        fi
        ;;
    esac
    return 0
}

check_command() { # check_command <command string>
    local line
    while IFS= read -r line; do
        check_segment "$line"
    done <<EOF
$(printf '%s\n' "$1" | split_parts)
EOF
    return 0
}

if [ -n "$fpath" ]; then
    edit_check "$fpath"
    exit 0
fi

# Fast path: most commands never mention git or a shell string.
case "$cmd" in
*git* | *" -c"* | *eval*) ;;
*) exit 0 ;;
esac

check_command "$cmd"
exit 0
