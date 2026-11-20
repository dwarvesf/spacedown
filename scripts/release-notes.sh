#!/usr/bin/env bash
# release-notes.sh: print the CHANGELOG.md section for one version, the body that
# scripts/release.sh publishes as the GitHub release notes.
#
#   scripts/release-notes.sh <x.y.z> [<changelog>]   (default: CHANGELOG.md at the repo root)
#
# Prints every line between "## [x.y.z]" and the next "## " heading, without the
# heading itself, the link references at the end of the file, or leading and
# trailing blank lines. Exit 1 when the section is missing or has no text, so a
# release never goes out with empty or wrong notes; exit 64 on bad usage.
# Runs under bash 3.2.
set -euo pipefail

VERSION="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${2:-$ROOT/CHANGELOG.md}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: release-notes.sh <x.y.z> [<changelog>]" >&2; exit 64; }
[[ -f "$LOG" ]] || { echo "release-notes: $LOG not found" >&2; exit 64; }

notes="$(awk -v head="## [$VERSION]" '
  index($0, "## ") == 1 { if (on) exit; if (index($0, head) == 1) { on = 1; next } }
  on && /^\[[^]]+\]: / { next }
  on { print }
' "$LOG" | awk 'NF { started = 1 } started { lines[++n] = $0; if (NF) last = n } END { for (i = 1; i <= last; i++) print lines[i] }')"

if [[ -z "$notes" ]]; then
  echo "release-notes: no \"## [$VERSION]\" section with text in ${LOG#"$ROOT/"}" >&2
  exit 1
fi
printf '%s\n' "$notes"
