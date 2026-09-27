#!/bin/bash
# Render the fixture through the exact Quick Look pipeline and screenshot it in light
# and dark, plus the app window, into the repo's docs/images for the README.
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$S/.." && pwd)}"
B="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
Q="$S/qlshot"
mkdir -p "$Q" "$REPO/docs/images"
cp -f "$REPO/tests/fixture/"*.svg "$Q/"
cp -f "$REPO/assets/vscode-preview-head.html" "$REPO/integrations/safari/quick-look/Resources/md-style.html"
node "$REPO/integrations/safari/quick-look/render-file.js" "$REPO/tests/fixture/fixture.md" --out "$Q/panel.html"
node "$S/qlwrap.js" "$Q/panel.html" "$REPO/integrations/safari/quick-look/Resources" "$Q/page.html"
"$B" --headless=new --disable-gpu --hide-scrollbars --window-size=900,1150 --screenshot="$REPO/docs/images/quicklook-light.png" "file://$Q/page.html" >/dev/null 2>&1
"$B" --headless=new --disable-gpu --hide-scrollbars --force-dark-mode --window-size=900,1150 --screenshot="$REPO/docs/images/quicklook-dark.png" "file://$Q/page.html" >/dev/null 2>&1
cp -f "$S/win-ql-light.png" "$REPO/docs/images/app-window.png"
ls -la "$REPO/docs/images"
