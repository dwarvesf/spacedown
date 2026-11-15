#!/usr/bin/env bash
# Assemble the EXACT page the Quick Look appex builds (katex.min.css +
# md-style.html + hljs-theme.css + ql-reading.css + ql-settings.css + plug-in css
# around the SD.render body) and shoot it in
# both appearances. Verifies the reading skin and its dark-mode block without
# a GUI, since the appex head is assembled in Swift and has no headless twin.
#
#   bash integrations/safari/quick-look/preview-skin.sh [file.md] [outdir]
# Needs node and npx (Playwright is fetched on first run).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QL="${HERE}"
MD="${1:-${HERE}/../../../tests/fixture/fixture.md}"
OUT="${2:-/tmp/ql-reading}"
mkdir -p "$OUT"

# md-style.html is build-copied into Resources by build-safari.sh and gitignored,
# so on a fresh checkout read its source instead.
BASE="${QL}/Resources/md-style.html"
[ -f "$BASE" ] || BASE="${HERE}/../../../assets/vscode-preview-head.html"

# SD.render gives the page parts buildPreviewHTML places: body, plug-in css, the
# top-of-body chrome (controls + toolbar) and the <html> attributes. Default settings.
node -e 'const fs = require("fs"); const p = require(process.argv[1]).loadCore().SD.render(fs.readFileSync(process.argv[2], "utf8"), {});
for (const k of ["body", "css", "chrome", "attrs"]) fs.writeFileSync(process.argv[3] + "/" + k + ".html", p[k]);' \
  "${QL}/load-core.js" "$MD" "$OUT"
{
  echo "<!doctype html><html lang=\"en\" $(cat "${OUT}/attrs.html")><head><meta charset=\"utf-8\">"
  # Same panel reset, in the same position, as buildPreviewHTML. Order is the
  # whole point: the reset must precede the stylesheets or it outdents the page.
  echo '<style>body { margin: 0; padding: 16px 22px; }</style>'
  echo "<style>$(cat "${QL}/Resources/katex.min.css")</style>"
  cat "$BASE"
  echo "<style>$(cat "${QL}/Resources/hljs-theme.css")</style>"
  # NO_SKIN=1 is the negative control: drop the reading skin and the page falls
  # back to the VS Code look, sans and light-only in both appearances.
  [ "${NO_SKIN:-0}" = "1" ] || echo "<style>$(cat "${QL}/Resources/ql-reading.css")</style>"
  echo "<style>$(cat "${QL}/Resources/ql-settings.css")</style>"
  [ -s "${OUT}/css.html" ] && echo "<style>$(cat "${OUT}/css.html")</style>"
  echo '</head><body>'
  cat "${OUT}/chrome.html" "${OUT}/body.html"
  echo '</body></html>'
} > "${OUT}/page.html"

for scheme in light dark; do
  npx --yes playwright screenshot --full-page --viewport-size=900,700 \
    --color-scheme="$scheme" "file://${OUT}/page.html" "${OUT}/${scheme}.png" >/dev/null
done
echo "wrote ${OUT}/light.png ${OUT}/dark.png"
