#!/usr/bin/env bash
# check-e2e.sh: a saved setting shows in a Quick Look render. Reads the stored settings
# with scripts/sd-settings (the group container plist the signed app writes), hands them
# to the appex's real page builder (buildPreviewHTML in MarkdownPreviewProvider.swift,
# compiled into a throwaway tool with the appex Resources beside it), and checks the
# page. The sandboxed appex itself is not launched: no Quick Look host runs it here.
#   bash docs/verification/r1-settings/check-e2e.sh
#   SPACEDOWN_PREFS=<plist> bash docs/verification/r1-settings/check-e2e.sh   (another plist)
# Expects textSize 24 and theme tm in the plist (the proof writes them first).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QL="${ROOT}/integrations/safari/quick-look"
WORK="$(mktemp -d)"
[ -f "${QL}/Resources/md-style.html" ] || cp "${ROOT}/assets/vscode-preview-head.html" "${QL}/Resources/md-style.html"
cp "${QL}"/Resources/* "${WORK}/"
cat > "${WORK}/main.swift" <<'SWIFT'
import Foundation
let json = FileHandle.standardInput.readDataToEndOfFile()
let settings = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
let md = "# Fixture\n\nOne paragraph of body text.\n"
FileHandle.standardOutput.write(buildPreviewHTML(md, settings: settings))
SWIFT
swiftc -O -o "${WORK}/render" "${WORK}/main.swift" "${QL}/Sources/MarkdownPreviewProvider.swift" \
  "${ROOT}/integrations/safari/shared/SpacedownSettings.swift" 2>&1 | grep -E "error" && exit 2
stored="$("${ROOT}/scripts/sd-settings")"
echo "stored: ${stored}" | cut -c1-120
html="$(printf '%s' "$stored" | "${WORK}/render")"
if [ -n "${DEBUG:-}" ]; then printf "%s" "$html" | head -c 600; echo; fi
fail=0
check() { if grep -qF -- "$1" <<<"$html"; then echo "ok   page has $1"; else echo "FAIL page lacks $1"; fail=1; fi; }
check 'style="--ql-size:24px"'
check 'data-sd-theme="tm"'
check '<h1'
[ $fail -eq 0 ] && echo "check-e2e: passed" || echo "check-e2e: FAILED"
exit $fail
