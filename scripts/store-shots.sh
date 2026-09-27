#!/bin/bash
# Re-compose Mac App Store screenshots 1 and 2 (2880x1800) from the real Quick Look
# render, in the fonts a typical user sees (system faces: the iA Writer faces only apply
# when installed). Screenshot 3 (app window) is kept as is.
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$S/.." && pwd)}"
OUT="${OUT:-$S/out}"
B="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
RES="$REPO/integrations/safari/quick-look/Resources"
mkdir -p "$OUT" "$S/qlshot" "$S/store"
cp -f "$REPO/assets/vscode-preview-head.html" "$RES/md-style.html"
SYS=':root{--ql-body-font:-apple-system,"Helvetica Neue",Arial,sans-serif;--ql-mono-font:ui-monospace,"SF Mono",Menlo,monospace}'
render() { # md -> page.html with the system-font override appended
  node "$REPO/integrations/safari/quick-look/render-file.js" "$1" --out "$S/qlshot/$2.body.html" >/dev/null
  node "$S/qlwrap.js" "$S/qlshot/$2.body.html" "$RES" "$S/qlshot/$2.html" >/dev/null
  printf '<style>%s</style>\n' "$SYS" >> "$S/qlshot/$2.html"
}
render "$S/launch.md" light
render "$S/showcase.md" dark

page() { # name headline sub page-file bodyclass
  cat > "$S/store/$1.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%}
body{width:1440px;height:900px;overflow:hidden;font-family:-apple-system,"SF Pro Display",system-ui,sans-serif;
  background:radial-gradient(120% 90% at 50% 0%,#6d6bf5 0%,#4f46e5 45%,#2e2896 100%);color:#fff;
  display:flex;flex-direction:column;align-items:center}
h1{margin:64px 0 0;font-size:54px;font-weight:700;letter-spacing:-1px}
p{margin:12px 0 0;font-size:22px;opacity:.85}
.win{margin-top:44px;width:1060px;height:640px;border-radius:14px;overflow:hidden;background:#fbfaf7;
  box-shadow:0 30px 80px rgba(10,8,60,.55),0 0 0 1px rgba(255,255,255,.15)}
.bar{height:34px;background:rgba(236,236,236,.96);display:flex;align-items:center;gap:8px;padding:0 14px}
.bar i{width:12px;height:12px;border-radius:50%;display:block}
.dark .win{background:#19191b}.dark .bar{background:#2a2a2c}
iframe{border:0;width:100%;height:606px;display:block}
</style></head><body class="$5"><h1>$2</h1><p>$3</p>
<div class="win"><div class="bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div><iframe src="../qlshot/$4.html"></iframe></div>
</body></html>
HTML
}
page 1-light "Press space. Read it rendered." "Markdown previews in Finder's Quick Look, no setup." light ""
page 2-dark "Math, tables, callouts, code." "A calm reading theme that follows light and dark mode." dark "dark"

shot() { "$B" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 $2 \
  --window-size=1440,900 --screenshot="$OUT/$1.png" "file://$S/store/$1.html" >/dev/null 2>&1; }
shot 1-light ""
shot 2-dark "--force-dark-mode"
for f in "$OUT"/*.png; do echo "$(basename "$f"): $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"; done
