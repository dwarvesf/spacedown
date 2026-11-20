#!/usr/bin/env bash
# release-notes-test.sh: scripts/release-notes.sh prints one version's CHANGELOG section,
# without its heading, the next section or the link references, and fails on a missing or
# empty section (the negative controls). Also checks the real CHANGELOG has a section for
# the version in project.yml, and that scripts/release.sh publishes those notes.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES="$ROOT/scripts/release-notes.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/release-notes-test.XXXXXX")"
pass=0; fail=0
ok() { echo "  ok   $1"; pass=$((pass + 1)); }
no() { echo "  FAIL $1"; fail=$((fail + 1)); }

cat > "$T/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [2.0.0] - 2026-01-02

### Added

- Feature two.

## [1.5.0] - 2025-12-01

### Fixed

- Bug one.

## [1.4.0] - 2025-11-01

[Unreleased]: https://example.com/compare/v2.0.0...HEAD
[2.0.0]: https://example.com/releases/tag/v2.0.0
EOF

OUT="$("$NOTES" 2.0.0 "$T/CHANGELOG.md")"; rc=$?
if [[ $rc -eq 0 && "$OUT" == "### Added"*"- Feature two." && "$OUT" != *"Bug one"* && "$OUT" != *"## [2.0.0]"* ]]; then
  ok "the section body alone, from its first line to its last"
else
  no "the section body alone (rc=$rc): $OUT"
fi
OUT="$("$NOTES" 1.5.0 "$T/CHANGELOG.md")"
if [[ "$OUT" == "### Fixed"*"- Bug one." ]]; then ok "a middle section stops at the next heading"; else no "middle section: $OUT"; fi
"$NOTES" 1.4.0 "$T/CHANGELOG.md" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 1 ]]; then ok "an empty last section fails (link references are not notes)"; else no "empty section rc=$rc"; fi
ERR="$("$NOTES" 9.9.9 "$T/CHANGELOG.md" 2>&1)"; rc=$?
if [[ $rc -eq 1 && "$ERR" == *'no "## [9.9.9]" section'* ]]; then ok "a missing version fails and says so"; else no "missing version rc=$rc: $ERR"; fi
"$NOTES" 2.0 "$T/CHANGELOG.md" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 64 ]]; then ok "a malformed version is a usage error"; else no "malformed version rc=$rc"; fi

VERSION="$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$ROOT/integrations/safari/quick-look/project.yml")"
if "$NOTES" "$VERSION" >/dev/null 2>&1; then ok "CHANGELOG.md has notes for $VERSION (project.yml)"; else no "CHANGELOG.md has no notes for $VERSION"; fi
if grep -q 'scripts/release-notes.sh' "$ROOT/scripts/release.sh" && ! grep -q -- '--notes "Quick Look preview' "$ROOT/scripts/release.sh"; then
  ok "release.sh publishes the CHANGELOG notes, no fixed string"
else
  no "release.sh does not use release-notes.sh"
fi

echo "release-notes-test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
