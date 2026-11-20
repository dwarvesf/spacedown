#!/usr/bin/env bash
# agent-kit-hook.sh - run one hook of the optional agent kit, or do nothing.
#
# Usage (from .claude/settings.json): bash scripts/agent-kit-hook.sh <hook.sh> [args...]
#
# A contributor without the kit has no ~/.claude/dwarves-kit, and a hook that
# points there would print an error on every tool call. This wrapper exits 0,
# silently, when the kit or the named hook is missing. When both exist it hands
# over to the kit's anchor-root.sh with the same arguments, stdin and exit code.
# DWARVES_KIT_DIR overrides the kit path (the tests use it). Bash 3.2 safe.
hook="${1-}"
case "$hook" in
"" | */* | *..*) exit 0 ;;
esac
shift
kit="${DWARVES_KIT_DIR:-$HOME/.claude/dwarves-kit}"
[ -f "$kit/hooks/anchor-root.sh" ] && [ -f "$kit/hooks/$hook" ] || exit 0
exec bash "$kit/hooks/anchor-root.sh" "$kit/hooks/$hook" "$@"
