#!/bin/bash
# Headless screenshots of the app window page: Quick Look only and with Safari,
# light and dark, at the window sizes ViewController sets.
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$S/.." && pwd)}"
RES="$REPO/integrations/safari/SpacedownDrop/SpacedownDrop/Resources"
B="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
W="$S/win"
mkdir -p "$W/Base.lproj"
cp -f "$RES/Style.css" "$RES/Script.js" "$W/"
cp -f "$RES/Base.lproj/Main.html" "$W/Base.lproj/ql.html"
sed 's/<section class="safari" hidden>/<section class="safari">/' "$RES/Base.lproj/Main.html" > "$W/Base.lproj/safari.html"
shot() { "$B" --headless=new --disable-gpu --hide-scrollbars $3 --window-size=460,$2 --screenshot="$S/win-$1.png" "file://$W/Base.lproj/$4" >/dev/null 2>&1; }
shot ql-light 500 "--force-device-scale-factor=2" ql.html
shot ql-dark 500 "--force-dark-mode" ql.html
shot safari-light 640 "" safari.html
ls "$S"/win-*.png
