#!/usr/bin/env bash
# katex-one-test.sh: the app carries one KaTeX, and the Quick Look panel and the CLI both draw
# math with it, fonts included.
#
#   bash tests/katex-one-test.sh [<built Spacedown.app>] [<screenshot dir>]
#
# Checks: (1) script, stylesheet and fonts are one pinned version; (2) scripts/build-ql-katex
# leaves no relative font url and embeds every woff2; (3) the page the panel builder assembles
# (the same head order as buildPreviewHTML, from the app's own extension when an app is given)
# and the CLI page (spacedown --offline --shot) both typeset the math fixture, with every
# KaTeX font the page uses loaded and none failed. The panel page keeps its CSP; a font the CSP
# blocks shows in the browser console and fails check 3. Needs node and a Chromium-family
# browser (SPACEDOWN_TEST_BROWSER, Helium, Chrome or Chromium); check 3 is skipped without one.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"
OUT="${2:-}"
PIN="0.19.0"
QL="$ROOT/integrations/safari/quick-look"
FIX="$ROOT/tests/fixture/math-fonts.md"
T="$(mktemp -d "${TMPDIR:-/tmp}/katex-one-test.XXXXXX")"
[[ -n "$OUT" ]] || OUT="$T/shots"
mkdir -p "$OUT"
pass=0; fail=0
ok() { echo "  ok   $1"; pass=$((pass + 1)); }
no() { echo "  FAIL $1"; fail=$((fail + 1)); }

echo "[1] one version"
js_v="$(grep -o 'version:"[0-9.]*"' "$QL/Resources/katex.min.js" | head -1 | sed 's/version:"//; s/"//')"
[[ "$js_v" == "$PIN" ]] && ok "katex.min.js is $PIN" || no "katex.min.js is $js_v, pinned $PIN"
if grep -q "| KaTeX (script, stylesheet and woff2 fonts, one version) | $PIN |" "$ROOT/THIRD_PARTY_NOTICES.md"; then ok "THIRD_PARTY_NOTICES names $PIN once for script, stylesheet and fonts"; else no "THIRD_PARTY_NOTICES does not name $PIN for all three"; fi
fonts_in_css="$(grep -o 'url(fonts/[^)]*\.woff2)' "$QL/Resources/katex.min.css" | sed 's/url(fonts\///; s/)//' | sort -u)"
missing=0; for f in $fonts_in_css; do [[ -f "$ROOT/assets/katex/fonts/$f" ]] || missing=$((missing + 1)); done
n_css="$(printf '%s\n' "$fonts_in_css" | wc -l | tr -d ' ')"
n_dir="$(ls "$ROOT/assets/katex/fonts" | grep -c '\.woff2$')"
[[ $missing -eq 0 && "$n_css" == "$n_dir" ]] && ok "the stylesheet names $n_css woff2 fonts, all in assets/katex/fonts, none extra" || no "stylesheet fonts $n_css vs directory $n_dir, $missing missing"

echo "[2] build-ql-katex"
"$ROOT/scripts/build-ql-katex" "$T/katex.css" >/dev/null 2>&1
n_uri="$(grep -o 'url(data:font/woff2;base64,' "$T/katex.css" | wc -l | tr -d ' ')"
if [[ "$n_uri" == "$n_dir" ]] && ! grep -q 'url(fonts/' "$T/katex.css" && ! grep -q '\.woff)\|\.ttf)' "$T/katex.css"; then ok "$n_uri fonts embedded as woff2 data URIs, no relative url, no woff or ttf left"; else no "embedded $n_uri of $n_dir fonts, or a relative/fallback url is left"; fi

if [[ -n "$APP" ]]; then
  EXT="$APP/Contents/PlugIns/SpacedownQL.appex/Contents/Resources"
  if cmp -s "$T/katex.css" "$EXT/katex.min.css"; then ok "the app's extension ships exactly that stylesheet"; else no "the app's extension stylesheet differs from build-ql-katex output"; fi
  if [[ ! -e "$APP/Contents/Resources/cli/assets/katex/fonts" && ! -e "$APP/Contents/Resources/cli/assets/katex/katex.min.js" ]] && [[ "$(find "$APP" -name 'KaTeX_*.woff2' | wc -l | tr -d ' ')" == "0" ]]; then ok "the bundled CLI carries no KaTeX script, stylesheet or font file; the app has no loose font"; else no "the app still carries a second KaTeX copy"; fi
else
  EXT="$T/ext"; mkdir -p "$EXT"
  rsync -a "$QL/Resources/" "$EXT/"; cp -f "$T/katex.css" "$EXT/katex.min.css"
fi

echo "[3] the panel page and the CLI page draw the math with the fonts"
BROWSER_BIN="${SPACEDOWN_TEST_BROWSER:-}"
for c in "$BROWSER_BIN" "/Applications/Helium.app/Contents/MacOS/Helium" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  [[ -n "$c" && -x "$c" ]] && { BROWSER_BIN="$c"; break; }
done
if [[ -z "$BROWSER_BIN" || ! -x "$BROWSER_BIN" ]] || ! command -v node >/dev/null 2>&1; then
  echo "  skip: no node or no Chromium-family browser"
else
  # Panel page: SD.render, then the head in buildPreviewHTML's order, with its CSP.
  node -e '
    const fs = require("fs"), path = require("path");
    const [ql, ext, fix, out] = process.argv.slice(1);
    const p = require(path.join(ql, "load-core.js")).loadCore().SD.render(fs.readFileSync(fix, "utf8"), {});
    const r = (n) => fs.readFileSync(path.join(ext, n), "utf8");
    const base = fs.existsSync(path.join(ext, "md-style.html")) ? r("md-style.html") : fs.readFileSync(path.join(ql, "../../../assets/vscode-preview-head.html"), "utf8");
    const head = `<style>${r("katex.min.css")}</style>\n${base}\n<style>${r("hljs-theme.css")}</style>\n<style>${r("ql-reading.css")}</style>\n<style>${r("ql-settings.css")}</style>\n` + (p.css ? `<style>${p.css}</style>\n` : "");
    const swift = fs.readFileSync(path.join(ql, "Sources/MarkdownPreviewProvider.swift"), "utf8");
    const csp = /content="(default-src [^"]*)"/.exec(swift)[1];
    const page = (cspTag, extra) => `<!doctype html>\n<html lang="en" ${p.attrs}><head><meta charset="utf-8">\n${cspTag}<style>body { margin: 0; padding: 16px 22px; }</style>\n${head}</head><body>${p.chrome}${p.body}${extra}</body></html>`;
    fs.writeFileSync(out + "/panel.html", page(`<meta http-equiv="Content-Security-Policy" content="${csp}">\n`, ""));
    fs.writeFileSync(out + "/panel-probe.html", page("", ""));
  ' "$QL" "$EXT" "$FIX" "$T"

  # The font probe runs in a copy without the CSP (the panel runs no script); it lists every
  # KaTeX face by load status once the page is idle.
  probe='<script>window.addEventListener("load",function(){var used={};Array.prototype.forEach.call(document.querySelectorAll(".katex *"),function(e){var f=getComputedStyle(e).fontFamily.split(",")[0].replace(/["\x27 ]/g,"");if(/^KaTeX_/.test(f))used[f]=1;});document.fonts.ready.then(function(){var st={};document.fonts.forEach(function(f){if(/KaTeX/.test(f.family)){var k=f.family+"-"+f.weight+"-"+f.style;st[k]=f.status;}});var loaded=0,err=0,none=0;for(var k in st){if(st[k]==="loaded")loaded++;else if(st[k]==="error")err++;}var typeset=document.querySelectorAll(".katex-html").length,red=document.querySelectorAll(".katex-error").length;document.documentElement.setAttribute("data-fonts",loaded+"|"+err+"|"+Object.keys(used).length+"|"+typeset+"|"+red+"|"+document.fonts.check("1em KaTeX_Main"));});});</script>'
  dom_probe() { # <html file> -> prints the data-fonts value
    local f="$1" prof
    { cat "$f"; printf '%s\n' "$probe"; } >| "${f%.html}-p.html"
    prof="$(mktemp -d "$T/prof.XXXXXX")"
    "$BROWSER_BIN" --headless=new "--user-data-dir=$prof" --disable-gpu --virtual-time-budget=8000 --host-resolver-rules="MAP * ~NOTFOUND" \
      --dump-dom "file://${f%.html}-p.html" >| "${f%.html}.dom" 2>/dev/null &
    local pid=$! i
    for i in $(seq 1 60); do grep -q '</html>' "${f%.html}.dom" 2>/dev/null && break; sleep 0.5; done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    grep -o 'data-fonts="[^"]*"' "${f%.html}.dom" | head -1 | sed 's/data-fonts="//; s/"$//'
  }
  verdict() { # <label> <probe value>
    local label="$1" v="$2" loaded err used typeset red chk
    IFS='|' read -r loaded err used typeset red chk <<<"$v"
    if [[ -n "$v" && "${loaded:-0}" -ge 10 && "$err" == "0" && "$red" == "0" && "${typeset:-0}" -ge 8 && "$chk" == "true" ]]; then
      ok "$label: $typeset formulas typeset, $loaded KaTeX font faces loaded ($used families used), 0 failed, 0 KaTeX errors"
    else
      no "$label: fonts loaded|failed|families|formulas|errors|Main-ok = '${v:-no DOM}'"
    fi
  }

  # Panel page (probe copy has no CSP, so this proves the stylesheet and the fonts; the CSP is checked below).
  verdict "panel page" "$(dom_probe "$T/panel-probe.html")"

  # CLI page, offline, through the real --offline --shot path.
  "$ROOT/bin/spacedown" "$FIX" --out "$T/cli.html" --no-open --offline --shot "$OUT/cli-math.png" >/dev/null 2>"$T/cli.err"
  if [[ -s "$OUT/cli-math.png" ]] && ! grep -q 'WARN katex' "$T/cli.err"; then ok "spacedown --offline --shot wrote $OUT/cli-math.png, no katex warning"; else no "spacedown --offline --shot: no PNG or a katex warning ($(head -c 200 "$T/cli.err"))"; fi
  verdict "CLI page" "$(dom_probe "$T/cli.html")"

  # Panel screenshot, with its CSP in place; console errors name a blocked font.
  prof="$(mktemp -d "$T/prof.XXXXXX")"
  "$BROWSER_BIN" --headless=new "--user-data-dir=$prof" --disable-gpu --hide-scrollbars --window-size=900,900 --virtual-time-budget=8000 \
    --enable-logging=stderr --v=0 "--screenshot=$OUT/panel-math.png" "file://$T/panel.html" >/dev/null 2>"$T/panel.log" &
  pid=$!
  for i in $(seq 1 60); do [[ -s "$OUT/panel-math.png" ]] && { sleep 1; break; }; sleep 0.5; done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  [[ -s "$OUT/panel-math.png" ]] && ok "panel screenshot: $OUT/panel-math.png" || no "panel screenshot not written"
  blocked="$(grep -ac 'Loading the font' "$T/panel.log")"
  if [[ "$blocked" == "0" ]]; then
    ok "the panel's own CSP (read from MarkdownPreviewProvider.swift) lets every embedded font load"
  else
    no "the panel CSP blocks $blocked embedded font load(s); buildPreviewHTML needs font-src data:"
  fi
fi

echo "katex-one-test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
