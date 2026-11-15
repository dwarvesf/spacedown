#!/usr/bin/env bash
# check-css.sh: assemble the page the Quick Look appex builds, once per case, with the
# settings a user could save, and read the computed style off it in a headless browser.
# Proves ql-settings.css turns data-sd-theme, data-sd-appearance and --ql-size into the
# reading look. Needs node and a Chromium browser (env BROWSER, default Helium).
#   bash docs/verification/r1-settings/check-css.sh
#   CSS=/dev/null bash docs/verification/r1-settings/check-css.sh    (negative control: no settings CSS)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QL="${ROOT}/integrations/safari/quick-look"
CSS="${CSS:-${QL}/Resources/ql-settings.css}"
BROWSER="${BROWSER:-/Applications/Helium.app/Contents/MacOS/Helium}"
[ -x "$BROWSER" ] || { echo "check-css: no browser at $BROWSER (set BROWSER)" >&2; exit 2; }
WORK="$(mktemp -d)"
BASE="${QL}/Resources/md-style.html"; [ -f "$BASE" ] || BASE="${ROOT}/assets/vscode-preview-head.html"

fail=0
# theme | appearance | Mac scheme | textSize | expected background | font must contain | expected font-size
CASES=(
  "ia|system|light|18|rgb(252, 252, 252)|iA Writer Quattro|18px"
  "ia|system|dark|18|rgb(26, 26, 26)|iA Writer Quattro|18px"
  "tm|system|light|22|rgb(255, 255, 255)|Georgia|22px"
  "paper|system|light|18|rgb(251, 250, 247)|iA Writer Quattro|18px"
  "paper|system|dark|18|rgb(31, 30, 28)|iA Writer Quattro|18px"
  "read|system|light|20|rgb(252, 252, 252)|Georgia|20px"
  "mono|system|light|18|rgb(252, 252, 252)|iA Writer Mono|18px"
  "tm|dark|light|32|rgb(27, 26, 25)|Georgia|32px"
  "paper|light|dark|12|rgb(251, 250, 247)|iA Writer Quattro|12px"
)
for c in "${CASES[@]}"; do
  IFS='|' read -r theme appearance scheme size want_bg want_font want_size <<<"$c"
  page="${WORK}/${theme}-${appearance}-${scheme}.html"
  MAC="$scheme" node -e '
    const fs = require("fs"); const mac = process.env.MAC === "dark" ? "all" : "not all"; const q = (t) => t.replace(/\(prefers-color-scheme: dark\)/g, mac); const p = require(process.argv[1]).loadCore().SD.render("# Title\n\nBody text.\n", {theme: process.argv[2], appearance: process.argv[3], textSize: +process.argv[4]});
    process.stdout.write("<!doctype html><html lang=\"en\" " + p.attrs + "><head><meta charset=\"utf-8\">");
    for (const f of process.argv.slice(5)) process.stdout.write(f === "-" ? "" : (f.endsWith(".html") ? q(fs.readFileSync(f, "utf8")) : "<style>" + q(fs.readFileSync(f, "utf8")) + "</style>"));
    process.stdout.write("<style>" + p.css + "</style></head><body>" + p.chrome + p.body + "<pre id=out></pre><script>var b=getComputedStyle(document.body),h=getComputedStyle(document.documentElement);document.getElementById(\"out\").textContent=JSON.stringify({bg:b.backgroundColor,font:b.fontFamily,size:h.fontSize});</script></body></html>");
  ' "${QL}/load-core.js" "$theme" "$appearance" "$size" \
    "${QL}/Resources/katex.min.css" "$BASE" "${QL}/Resources/hljs-theme.css" "${QL}/Resources/ql-reading.css" "$CSS" > "$page"
  dom="$("$BROWSER" --headless --disable-gpu --user-data-dir="${WORK}/profile-${theme}-${appearance}-${scheme}" \
    --dump-dom "file://${page}" 2>/dev/null)"
  json="$(printf '%s' "$dom" | sed -n 's/.*<pre id="out">\(.*\)<\/pre>.*/\1/p' | sed 's/&quot;/"/g')"
  got_bg="$(printf '%s' "$json" | sed -n 's/.*"bg":"\([^"]*\)".*/\1/p')"
  got_font="$(printf '%s' "$json" | sed -n 's/.*"font":"\(.*\)","size".*/\1/p')"
  got_size="$(printf '%s' "$json" | sed -n 's/.*"size":"\([^"]*\)".*/\1/p')"
  if [ "$got_bg" = "$want_bg" ] && [[ "$got_font" == *"$want_font"* ]] && [ "$got_size" = "$want_size" ]; then
    echo "ok   ${theme} appearance=${appearance} mac=${scheme} size=${size}: ${got_bg} ${got_size}"
  else
    echo "FAIL ${theme} appearance=${appearance} mac=${scheme} size=${size}: want ${want_bg} / ${want_font} / ${want_size}, got ${got_bg} / ${got_font} / ${got_size}"
    fail=1
  fi
done
[ $fail -eq 0 ] && echo "check-css: all ${#CASES[@]} cases passed" || echo "check-css: FAILED"
exit $fail
