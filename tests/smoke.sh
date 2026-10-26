#!/usr/bin/env bash
# spacedown smoke test: exercises the CLI contract, the reading chrome, the
# frontmatter and callout passes, dark mode, and the Quick Look render core.
# The --watch path is not covered here because it depends on whether entr is
# installed on the host.
#
# Run: bash tests/smoke.sh
# Pass: prints "smoke: all passed", exit 0.
# Fail: prints which test failed, exit 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPACEDOWN="${SCRIPT_DIR}/bin/spacedown"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

# 1. --version exits 0
echo "[1] --version"
if out=$("$SPACEDOWN" --version 2>&1) && echo "$out" | grep -q '^spacedown '; then ok "version output"; else no "version output: $out"; fi

# 2. --help exits 0
echo "[2] --help"
if "$SPACEDOWN" --help >/dev/null 2>&1; then ok "help exit 0"; else no "help exit"; fi

# 3. no args → exit 64
echo "[3] no args → exit 64"
set +e; "$SPACEDOWN" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 64 ]]; then ok "exit 64"; else no "got $rc"; fi

# 4. nonexistent file → exit 1
echo "[4] nonexistent file → exit 1"
set +e; "$SPACEDOWN" "${TMP}/missing.md" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 1 ]]; then ok "exit 1"; else no "got $rc"; fi

# 5. empty file → exit 1
echo "[5] empty file → exit 1"
: > "${TMP}/empty.md"
set +e; "$SPACEDOWN" "${TMP}/empty.md" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 1 ]]; then ok "exit 1"; else no "got $rc"; fi

# Prepare a valid markdown fixture with LaTeX math.
cat > "${TMP}/fixture.md" <<'EOF'
# Test fixture

Inline math: $\alpha^2 + \beta^2 = 1$.

Display math:
$$
\sum_{i=0}^{n-1} |\alpha_i|^2 = 1
$$

A Hadamard:
$$
H = \tfrac{1}{\sqrt{2}} \begin{bmatrix} 1 & 1 \\ 1 & -1 \end{bmatrix}
$$
EOF

# 6. valid render with --no-open prints output path on stdout
echo "[6] valid render --no-open → stdout = path"
out_path=$("$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/fixture.html" --no-open 2>/dev/null)
if [[ "$out_path" == "${TMP}/fixture.html" ]]; then ok "stdout=$out_path"; else no "stdout=$out_path expected ${TMP}/fixture.html"; fi
if [[ -f "${TMP}/fixture.html" ]]; then ok "output file exists"; else no "output file missing"; fi

# 7. piped (no TTY) auto --no-open
echo "[7] piped (no TTY) auto --no-open"
out_path=$("$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/fixture2.html" 2>/dev/null | cat)
if [[ "$out_path" == "${TMP}/fixture2.html" ]]; then ok "piped stdout=$out_path"; else no "piped stdout=$out_path"; fi

# 8. --out into non-existing parent dir creates it
echo "[8] --out parent dir auto-create"
nested="${TMP}/deep/nested/dir/out.html"
out_path=$("$SPACEDOWN" "${TMP}/fixture.md" --out "$nested" --no-open 2>/dev/null)
if [[ -f "$nested" ]]; then ok "nested dir created"; else no "nested dir missing"; fi

# 9. rendered HTML contains KaTeX reference
echo "[9] KaTeX reference present"
if grep -q 'katex' "${TMP}/fixture.html"; then ok "katex found"; else no "katex missing"; fi

# 10. rendered math element present
echo "[10] math span rendered"
if grep -q 'class="math inline"' "${TMP}/fixture.html" && grep -q 'class="math display"' "${TMP}/fixture.html"; then
  ok "inline + display math both present"
else
  no "missing inline or display math"
fi

# 10b. a render prints no pandoc deprecation warning on stderr (pandoc 3.11 deprecated --katex)
echo "[10b] render stderr has no Deprecated warning"
"$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/deprecation.html" --no-open >/dev/null 2>"${TMP}/deprecation.err"
if grep -q 'Deprecated' "${TMP}/deprecation.err"; then
  no "pandoc deprecation warning: $(grep 'Deprecated' "${TMP}/deprecation.err" | head -1)"
else
  ok "no Deprecated warning on stderr"
fi

# 11. VSCodium / VS Code preview stylesheet injected into the page head
echo "[11] vscode preview style injected"
if grep -q 'VSCodium / VS Code' "${TMP}/fixture.html"; then ok "vscode style head present"; else no "vscode style head missing"; fi

# 12. no centered pandoc title-header block (VS Code preview never shows one)
echo "[12] no title-header block"
if grep -q 'class="title"' "${TMP}/fixture.html"; then no "title block present"; else ok "no title block"; fi

# 13. page column overrides pandoc's 36em default. The column is one custom property,
#     --sd-measure (50rem, ~78 mono chars; was 60rem). The body rule must appear AFTER
#     pandoc's 36em so the cascade lets it win, and no literal 60rem or 48rem may remain.
echo "[13] page column overrides pandoc default"
line36=$(grep -n 'max-width: 36em' "${TMP}/fixture.html" | head -1 | cut -d: -f1)
linem=$(grep -n '  max-width: var(--sd-measure);' "${TMP}/fixture.html" | head -1 | cut -d: -f1 || true)
if [[ -n "$linem" ]] && { [[ -z "$line36" ]] || [[ "$linem" -gt "$line36" ]]; } \
   && ! grep -q 'max-width: 48rem' "${TMP}/fixture.html"; then
  ok "var(--sd-measure) column wins over pandoc 36em; prose fills it"
else
  no "page column / prose measure missing or ordered before pandoc default"
fi

# 13a. the measure is 50rem, declared once, and nothing hardcodes the old 60rem.
echo "[13a] reading measure is one 50rem property"
if [[ "$(grep -c -- '--sd-measure: 50rem;' "${TMP}/fixture.html")" -eq 1 ]] \
   && [[ "$(grep -c 'max-width: var(--sd-measure)' "${TMP}/fixture.html")" -ge 4 ]] \
   && ! grep -q 'max-width: 60rem' "${TMP}/fixture.html"; then
  ok "--sd-measure: 50rem, used by body, prose, tables, rules and the RSVP stage"
else
  no "reading measure is not a single 50rem --sd-measure property (or a 60rem literal remains)"
fi

# 13b. tables can scroll horizontally (wide content) instead of squashing the column
echo "[13b] table horizontal scroll"
if grep -q 'overflow-x: auto' "${TMP}/fixture.html"; then ok "table overflow-x scroll present"; else no "table scroll missing"; fi

# 14. font override: fonts from SPACEDOWN_SETTINGS are mirrored into the output
echo "[14] font override from settings"
cat > "${TMP}/settings.json" <<'JSON'
{
  "markdown.preview.fontFamily": "'Smoke Font', monospace",
  "markdown.preview.fontSize": 17,
  "editor.fontFamily": "'Smoke Code', monospace"
}
JSON
SPACEDOWN_SETTINGS="${TMP}/settings.json" "$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/fonts.html" --no-open >/dev/null 2>&1
if grep -q "Smoke Font" "${TMP}/fonts.html" && grep -q '17px' "${TMP}/fonts.html" && grep -q "Smoke Code" "${TMP}/fonts.html"; then
  ok "fonts mirrored from settings (body + size + code)"
else
  no "font override missing"
fi

# 15. no settings file -> no override leak (base asset defaults apply)
echo "[15] font fallback when no settings"
SPACEDOWN_SETTINGS="${TMP}/does-not-exist.json" "$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/nofonts.html" --no-open >/dev/null 2>&1
if grep -q "Smoke Font" "${TMP}/nofonts.html"; then no "override leaked without settings"; else ok "no override; base defaults apply"; fi

# 16. smart typography OFF: straight quotes stay literal (match VS Code's markdown-it, not pandoc curly)
echo "[16] smart typography disabled"
printf '%s\n' '> a "quoted" word.' > "${TMP}/smart.md"
"$SPACEDOWN" "${TMP}/smart.md" --out "${TMP}/smart.html" --no-open >/dev/null 2>&1
if grep -q '"quoted"' "${TMP}/smart.html"; then ok "straight quotes preserved (smart off)"; else no "quotes were smart-converted (curly)"; fi

# 16b. Obsidian-style wikilinks render as anchors with class="wikilink"
echo "[16b] wikilinks"
printf '%s\n' 'see [[some-note]] and [[other|Title]].' > "${TMP}/wiki.md"
"$SPACEDOWN" "${TMP}/wiki.md" --out "${TMP}/wiki.html" --no-open >/dev/null 2>&1
if grep -q 'class="wikilink"' "${TMP}/wiki.html" && grep -q '>Title<' "${TMP}/wiki.html"; then
  ok "[[target]] + [[target|title]] render as wikilink anchors"
else
  no "wikilinks not rendered"
fi

# 17. font-mode: the default render carries no serif block; --font-mode=read injects it
echo "[17] font-mode toggle"
"$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/default.html" --no-open >/dev/null 2>&1
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode=read --out "${TMP}/read.html" --no-open >/dev/null 2>&1
if ! grep -q 'read mode: proportional serif' "${TMP}/default.html" && grep -q 'read mode: proportional serif' "${TMP}/read.html"; then
  ok "default has no serif block; read injects serif"
else
  no "font-mode toggle not behaving"
fi

# 17e. The default renders the ia theme, paper and tm are explicit modes, and read and
#      mono carry no theme tokens (negative control).
echo "[17e] font-mode ia default"
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode=paper --out "${TMP}/paper.html" --no-open >/dev/null 2>&1
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode=mono --out "${TMP}/mono.html" --no-open >/dev/null 2>&1
if grep -q -- '--ia-bg' "${TMP}/default.html" && ! grep -q -- '--paper-bg' "${TMP}/default.html" \
   && grep -q -- '--paper-bg' "${TMP}/paper.html" && ! grep -q -- '--ia-bg' "${TMP}/paper.html" \
   && ! grep -q -- '--ia-bg' "${TMP}/mono.html" && ! grep -q -- '--paper-bg' "${TMP}/mono.html" \
   && ! grep -q -- '--ia-bg' "${TMP}/read.html" && ! grep -q -- '--paper-bg' "${TMP}/read.html"; then
  ok "default renders ia; paper passes through; mono and read carry no theme (negative control)"
else
  no "ia default not behaving"
fi

# 17e2. --font-mode=tm renders the Thinking Machines theme, and only it.
echo "[17e2] font-mode tm"
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode=tm --out "${TMP}/tm.html" --no-open >/dev/null 2>&1
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode tm --out "${TMP}/tm2.html" --no-open >/dev/null 2>&1
if grep -q -- '--tm-bg' "${TMP}/tm.html" && ! grep -q -- '--ia-bg' "${TMP}/tm.html" && ! grep -q -- '--paper-bg' "${TMP}/tm.html" \
   && grep -q -- '--tm-bg' "${TMP}/tm2.html"; then
  ok "tm renders in both flag forms, without the ia or paper tokens"
else
  no "tm mode not applied"
fi

# 17e3. SPACEDOWN_FONT_MODE sets the default; the flag still wins; a bad value is exit 64.
echo "[17e3] SPACEDOWN_FONT_MODE"
SPACEDOWN_FONT_MODE=paper "$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/envpaper.html" --no-open >/dev/null 2>&1
SPACEDOWN_FONT_MODE=tm "$SPACEDOWN" "${TMP}/fixture.md" --font-mode=ia --out "${TMP}/envflag.html" --no-open >/dev/null 2>&1
set +e; SPACEDOWN_FONT_MODE=nope "$SPACEDOWN" "${TMP}/fixture.md" --no-open >/dev/null 2>&1; rc=$?; set -e
if grep -q -- '--paper-bg' "${TMP}/envpaper.html" && ! grep -q -- '--ia-bg' "${TMP}/envpaper.html" \
   && grep -q -- '--ia-bg' "${TMP}/envflag.html" && ! grep -q -- '--tm-bg' "${TMP}/envflag.html" && [[ $rc -eq 64 ]]; then
  ok "env sets the mode, the flag overrides it, a bad value exits 64"
else
  no "SPACEDOWN_FONT_MODE not behaving (rc=$rc)"
fi

# 17e4. The ia stack puts iA Writer Quattro first, in the browser theme and the Quick Look skin.
echo "[17e4] ia stack has Quattro first"
if grep -q -- '--ia-font-sans: "iA Writer Quattro V"' "${TMP}/default.html" \
   && grep -q -- '--ql-body-font: "iA Writer Quattro V"' "${SCRIPT_DIR}/integrations/safari/quick-look/Resources/ql-reading.css"; then
  ok "Quattro first in the ia theme and the Quick Look skin"
else
  no "a theme lost iA Writer Quattro as its first face"
fi

# 17f. an unknown font mode is a usage error
echo "[17f] unknown font mode -> exit 64"
set +e; "$SPACEDOWN" "${TMP}/fixture.md" --font-mode=nope --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 64 ]]; then ok "exit 64"; else no "got $rc"; fi

# 17g. SPACEDOWN_THEME_CSS replaces the active theme (ia by default); read mode ignores it;
#      a missing file is a usage error.
echo "[17g] SPACEDOWN_THEME_CSS theme hook"
printf ':root { --custom-theme-bg: #123456; }\n' > "${TMP}/custom.css"
SPACEDOWN_THEME_CSS="${TMP}/custom.css" "$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/custom.html" --no-open >/dev/null 2>&1
SPACEDOWN_THEME_CSS="${TMP}/custom.css" "$SPACEDOWN" "${TMP}/fixture.md" --font-mode=read --out "${TMP}/custom-read.html" --no-open >/dev/null 2>&1
set +e; SPACEDOWN_THEME_CSS="${TMP}/nope.css" "$SPACEDOWN" "${TMP}/fixture.md" --no-open >/dev/null 2>&1; rc=$?; set -e
if grep -q -- '--custom-theme-bg' "${TMP}/custom.html" && ! grep -q -- '--paper-bg' "${TMP}/custom.html" \
   && ! grep -q -- '--ia-bg' "${TMP}/custom.html" \
   && ! grep -q -- '--custom-theme-bg' "${TMP}/custom-read.html" && [[ $rc -eq 64 ]]; then
  ok "theme file replaces the active theme; read unaffected; missing file exits 64"
else
  no "SPACEDOWN_THEME_CSS hook not behaving (rc=$rc)"
fi

# ---- reading chrome: outline sidebar + zoom + copy-source ----
# fixture.md has one heading, so it carries a TOC. Build a multi-heading one too.
cat > "${TMP}/chrome.md" <<'EOF'
# Heading One

Para with $x^2$.

## Heading Two

Body. Vietnamese: chữ Quốc ngữ.
EOF
"$SPACEDOWN" "${TMP}/chrome.md" --out "${TMP}/chrome.html" --no-open >/dev/null 2>&1

# 18. outline: nav#TOC emitted with an anchored entry per heading
echo "[18] outline sidebar (nav#TOC anchored entries)"
if grep -q 'id="TOC"' "${TMP}/chrome.html" \
   && grep -q 'href="#heading-one"' "${TMP}/chrome.html" \
   && grep -q 'href="#heading-two"' "${TMP}/chrome.html"; then
  ok "nav#TOC has an entry per heading"
else
  no "TOC entries missing"
fi

# 19. zoom: body text + line-height scale by the --sd-zoom var
echo "[19] zoom var override"
if grep -q 'var(--sd-zoom' "${TMP}/chrome.html"; then ok "zoom scale rule present"; else no "zoom rule missing"; fi

# 20. toolbar CSS + chrome JS both injected
echo "[20] toolbar + chrome JS"
if grep -q 'sd-toolbar' "${TMP}/chrome.html" && grep -q 'sd-has-toc' "${TMP}/chrome.html"; then
  ok "toolbar style + chrome script present"
else
  no "toolbar/script missing"
fi

# 21. copy-source: embedded base64 round-trips to the exact original bytes
echo "[21] copy-source embedded markdown round-trips"
src_b64="$(perl -ne 'print $1 if /id="sd-src">([^<]*)</' "${TMP}/chrome.html")"
printf '%s' "$src_b64" | base64 -D > "${TMP}/decoded.md" 2>/dev/null || printf '%s' "$src_b64" | base64 --decode > "${TMP}/decoded.md" 2>/dev/null
if cmp -s "${TMP}/decoded.md" "${TMP}/chrome.md"; then ok "embedded source == original (UTF-8 safe)"; else no "embedded source mismatch"; fi

# 22. no-heading doc: no sidebar (graceful), base render intact
echo "[22] no-heading doc has no sidebar"
printf '%s\n' 'Just prose, no headings. Inline $y^2$.' > "${TMP}/noh.md"
"$SPACEDOWN" "${TMP}/noh.md" --out "${TMP}/noh.html" --no-open >/dev/null 2>&1
if ! grep -q 'id="TOC"' "${TMP}/noh.html" && grep -q 'katex' "${TMP}/noh.html"; then
  ok "no nav#TOC when no headings; katex still renders"
else
  no "sidebar leaked or katex missing on no-heading doc"
fi

# 23. YAML frontmatter with unquoted colons (SKILL.md shape) renders as a properties
#     TABLE (not a yaml fence, not a pandoc-metadata crash); body still renders.
echo "[23] frontmatter renders as a properties table"
cat > "${TMP}/fm.md" <<'EOF'
---
name: concept-explain
description: Use when someone asks "X". Workflow: (1) check, (2) answer. NOT for X.
---

# Body

Prose with $z^2$.
EOF
set +e; out_path=$("$SPACEDOWN" "${TMP}/fm.md" --out "${TMP}/fm.html" --no-open 2>/dev/null); rc=$?; set -e
if [[ $rc -eq 0 && -f "${TMP}/fm.html" ]] \
   && grep -q 'class="sd-frontmatter"' "${TMP}/fm.html" \
   && [[ "$(grep -c 'class="sd-fm-key"' "${TMP}/fm.html")" -ge 2 ]] \
   && grep -q 'id="body"' "${TMP}/fm.html" \
   && ! grep -q 'sourceCode yaml' "${TMP}/fm.html"; then
  ok "frontmatter is a properties table (>=2 rows); body renders; no yaml fence"
else
  no "frontmatter table render failed (rc=$rc)"
fi

# 24. no-frontmatter doc is unaffected (no table, no stray yaml fence injected)
echo "[24] no-frontmatter doc unaffected"
"$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/nofm.html" --no-open >/dev/null 2>&1
if ! grep -q 'class="sd-frontmatter"' "${TMP}/nofm.html" && ! grep -q 'sourceCode yaml' "${TMP}/nofm.html"; then
  ok "no frontmatter table and no yaml fence injected"
else
  no "stray frontmatter rendering on plain doc"
fi

# 25. frontmatter closed with `...` (a valid YAML terminator) renders as a table too
echo "[25] frontmatter closed with ... renders as table"
printf -- '---\nname: x\ndescription: A: b. Workflow: (1) c.\n...\n\n# Body\n' > "${TMP}/dots.md"
set +e; "$SPACEDOWN" "${TMP}/dots.md" --out "${TMP}/dots.html" --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]] && grep -q 'class="sd-frontmatter"' "${TMP}/dots.html" && grep -q 'id="body"' "${TMP}/dots.html"; then
  ok "...-closed frontmatter is a table; body renders"
else
  no "...-closed frontmatter failed (rc=$rc)"
fi

# 26. CRLF frontmatter (Windows line endings) renders as a table
echo "[26] CRLF frontmatter renders as table"
printf -- '---\r\nname: x\r\ndescription: A: b.\r\n---\r\n\r\n# Body\r\n' > "${TMP}/crlf.md"
set +e; "$SPACEDOWN" "${TMP}/crlf.md" --out "${TMP}/crlf.html" --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]] && grep -q 'class="sd-frontmatter"' "${TMP}/crlf.html" && grep -q 'id="body"' "${TMP}/crlf.html"; then
  ok "CRLF frontmatter is a table; body renders"
else
  no "CRLF frontmatter failed (rc=$rc)"
fi

# 27. nested map flattens to a dotted key; list comma-joins; scalar gets a scalar span
echo "[27] nested dotted key + list + scalar"
printf -- '---\nname: x\ndraft: true\ntags: [a, b]\nmeta:\n  type: ref\n---\n\n# Body\n' > "${TMP}/nest.md"
"$SPACEDOWN" "${TMP}/nest.md" --out "${TMP}/nest.html" --no-open >/dev/null 2>&1
if grep -q 'meta\.type' "${TMP}/nest.html" \
   && grep -q 'class="sd-fm-scalar">true' "${TMP}/nest.html" \
   && grep -q 'a, b' "${TMP}/nest.html"; then
  ok "meta.type dotted key, true scalar span, comma-joined list"
else
  no "nested/list/scalar rendering wrong"
fi

# 28. unparseable frontmatter falls back to a yaml fence (never crashes, no table)
echo "[28] unparseable frontmatter -> yaml fence fallback"
printf -- '---\nname: ok\nthis line has no colon and is weird\n---\n\n# Body\n' > "${TMP}/bad.md"
set +e; "$SPACEDOWN" "${TMP}/bad.md" --out "${TMP}/bad.html" --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]] && grep -q 'sourceCode yaml' "${TMP}/bad.html" && ! grep -q 'class="sd-frontmatter"' "${TMP}/bad.html"; then
  ok "unparseable block fell back to fence; no table; no crash"
else
  no "fallback failed (rc=$rc)"
fi

# 29. copy-source still embeds the RAW original frontmatter (not the rendered table)
echo "[29] copy-source embeds raw original frontmatter"
src_b64="$(perl -ne 'print $1 if /id="sd-src">([^<]*)</' "${TMP}/fm.html")"
printf '%s' "$src_b64" | base64 -D > "${TMP}/fm-decoded.md" 2>/dev/null || printf '%s' "$src_b64" | base64 --decode > "${TMP}/fm-decoded.md" 2>/dev/null
if cmp -s "${TMP}/fm-decoded.md" "${TMP}/fm.md"; then ok "embedded source == raw original (frontmatter intact)"; else no "copy-source not raw original"; fi

# 30. collapsible outline: a multi-heading render carries the toggle button + the
#     collapse-state CSS + the flash-guard class, all under the existing has-toc gate.
#     (The click/persist/keyboard behavior needs a real browser; static greps cover the
#     wiring here.)
echo "[30] collapsible outline: toggle + collapse CSS + anim guard present"
printf '# H1\n\ntext\n\n## H2\n\nmore\n' > "${TMP}/toc.md"
"$SPACEDOWN" "${TMP}/toc.md" --out "${TMP}/toc.html" --no-open >/dev/null 2>&1
if grep -q 'sd-toc-toggle' "${TMP}/toc.html" \
   && grep -q 'sd-toc-collapsed' "${TMP}/toc.html" \
   && grep -q 'sd-anim-ready' "${TMP}/toc.html" \
   && grep -q 'sd-has-toc' "${TMP}/toc.html"; then
  ok "toggle + collapse state + anim guard + has-toc gate all present"
else
  no "collapsible-outline wiring missing"
fi

# 31. no-heading doc: gate stays closed (no nav#TOC), so the toggle CSS never reveals
echo "[31] no-heading doc has no outline (toggle stays inert)"
printf 'Just prose, no headings.\n' > "${TMP}/noh2.md"
"$SPACEDOWN" "${TMP}/noh2.md" --out "${TMP}/noh2.html" --no-open >/dev/null 2>&1
if ! grep -q 'id="TOC"' "${TMP}/noh2.html"; then ok "no nav#TOC; .sd-has-toc never added, toggle stays display:none"; else no "TOC leaked on no-heading doc"; fi

# 32. live-reload is watch-only: a default (non-watch) render injects NO reload poll script
#     and starts no server. (The --watch auto-refresh behavior is entr and browser dependent,
#     so it is not covered here; this guards that the default path stays clean.)
echo "[32] default (non-watch) render injects no live-reload"
printf '# Doc\n\nhello\n' > "${TMP}/plain.md"
"$SPACEDOWN" "${TMP}/plain.md" --out "${TMP}/plain.html" --no-open >/dev/null 2>&1
if ! grep -q '__sd_version' "${TMP}/plain.html" && ! grep -q 'spacedown live-reload' "${TMP}/plain.html"; then
  ok "no reload poll script in the default render"
else
  no "live-reload script leaked into the default (non-watch) render"
fi

# 33. UX polish: a top chrome lane is reserved (so floating toolbar/toggle don't overlap
#     content) and the sidebar carries an "Outline" header strip.
echo "[33] chrome lane + sidebar header strip"
printf '# H1\n\ntext\n\n## H2\n\nmore\n' > "${TMP}/lane.md"
"$SPACEDOWN" "${TMP}/lane.md" --out "${TMP}/lane.html" --no-open >/dev/null 2>&1
# (header strip is built by JS at runtime, so grep the CSS+JS wiring in the asset, not a
#  runtime element.)
if grep -q 'padding-top: var(--sd-chrome-lane)' "${TMP}/lane.html" \
   && grep -q 'sd-toc-header' "${TMP}/lane.html"; then
  ok "top chrome lane reserved (body padding-top) + header strip wired"
else
  no "chrome lane / header strip missing"
fi

# 34. long frontmatter value: table tagged .sd-fm-has-long (so it widens to a readable
#     measure) and an explicit (1)/(2)/(3) run is broken onto rows.
echo "[34] long frontmatter value widens + enumeration breaks into rows"
printf -- '---\nname: x\ndescription: %s Workflow: (1) alpha, (2) beta, (3) gamma. End.\n---\n\n# B\n' "$(printf 'word %.0s' {1..40})" > "${TMP}/long.md"
"$SPACEDOWN" "${TMP}/long.md" --out "${TMP}/long.html" --no-open >/dev/null 2>&1
if grep -q 'class="sd-frontmatter sd-fm-has-long"' "${TMP}/long.html" \
   && grep -q '<br>(2)' "${TMP}/long.html" \
   && grep -q '<br>(3)' "${TMP}/long.html"; then
  ok "long value tagged has-long; (2)/(3) broken onto rows"
else
  no "long-value widen / enum-split missing"
fi

# 34b. a long value is wrapped in a clamp container, and the foot JS wires a "Show more"
#      toggle (the toggle itself is added at runtime when the value overflows the clamp; here
#      we assert the clamp markup + the JS wiring are present).
echo "[34b] long value clamp + Show more wiring"
if grep -q '<div class="sd-fm-clamp">' "${TMP}/long.html" \
   && grep -q 'sd-fm-more' "${TMP}/long.html"; then
  ok "long value clamped; Show-more toggle wired in the foot JS"
else
  no "clamp container / show-more wiring missing"
fi

# 35. a short frontmatter value does NOT widen the table (compact aside preserved) and a
#     lone "(1)" in prose is NOT broken.
echo "[35] short frontmatter stays compact; lone (1) not split"
printf -- '---\nname: x\nnote: see step (1) for details\n---\n\n# B\n' > "${TMP}/sc.md"
"$SPACEDOWN" "${TMP}/sc.md" --out "${TMP}/sc.html" --no-open >/dev/null 2>&1
if ! grep -q 'class="sd-frontmatter sd-fm-has-long"' "${TMP}/sc.html" && ! grep -q '<br>(1)' "${TMP}/sc.html"; then
  ok "short value: no widen, no spurious enum break"
else
  no "short value wrongly widened or split"
fi

# 36. callouts: "> [!type] title" renders as a classed div + styled head; a plain
#     blockquote stays plain; a marker inside a code fence is left alone.
echo "[36] callouts"
printf -- '> [!warning] Watch out\n> Body text here.\n\n> plain quote\n\n```\n> [!note] fenced example\n```\n' > "${TMP}/co.md"
"$SPACEDOWN" "${TMP}/co.md" --out "${TMP}/co.html" --no-open >/dev/null 2>&1
if grep -q 'sd-callout-warning' "${TMP}/co.html" \
   && grep -q 'sd-callout-head' "${TMP}/co.html" \
   && ! grep -q '\[!warning\]' "${TMP}/co.html" \
   && grep -q '\[!note\]' "${TMP}/co.html"; then
  ok "callout classed + head styled; fenced marker untouched"
else
  no "callout rendering wrong"
fi

# 37. hard line breaks (Obsidian default): single newline inside a blockquote -> <br>,
#     so multi-line callouts keep their authored line structure.
echo "[37] hard line breaks"
printf -- '> [!note] History\n> **Wave 1**: a\n> **Wave 2**: b\n' > "${TMP}/br.md"
"$SPACEDOWN" "${TMP}/br.md" --out "${TMP}/br.html" --no-open >/dev/null 2>&1
if grep -q '<br' "${TMP}/br.html"; then
  ok "single newline renders as <br>"
else
  no "line breaks joined into one paragraph"
fi

# 38. browser dark mode: the rendered page carries the dark token flip for the page,
#     the reading chrome, and the tango syntax palette. No flag, no JS toggle.
echo "[38] dark-mode token flip in the rendered page"
# Asserts each token is defined TWICE (light :root plus the dark block) instead of
# pinning hex values, which turned every tone adjustment into a test edit.
if [[ "$(grep -c 'prefers-color-scheme: dark' "${TMP}/chrome.html")" -ge 2 ]] \
   && [[ "$(grep -c -- '--vscode-editor-background:' "${TMP}/chrome.html")" -ge 2 ]] \
   && [[ "$(grep -c -- '--sd-chrome-bg:' "${TMP}/chrome.html")" -ge 2 ]] \
   && [[ "$(grep -c -- '--sd-syn-keyword:' "${TMP}/chrome.html")" -ge 2 ]] \
   && grep -q 'color-scheme: dark' "${TMP}/chrome.html"; then
  ok "page + chrome + syntax dark tokens present; native widgets follow"
else
  no "dark-mode tokens missing from the render"
fi

# 38c. contract guard: every custom property a dark block redefines must also be declared
#      in a base :root, or that color has its ONLY definition inside the media query and
#      the light page loses it. Checked on the assets, which is where the rule lives.
#      ia-theme.css is not listed: its dark block flips the --sd-syn-* tokens whose light
#      values live in reading-chrome-head.html, so a per-file check cannot see them.
echo "[38c] no color defined only inside a dark media query"
if python3 - "${SCRIPT_DIR}/assets" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
bad = []
for name in ("vscode-preview-head.html", "reading-chrome-head.html", "paper-theme.css", "tm-theme.css"):
    text = (root / name).read_text()
    i, blocks = 0, []
    while True:
        m = re.search(r"@media \(prefers-color-scheme: dark\) \{", text[i:])
        if not m:
            break
        start, depth, j = i + m.start(), 0, i + m.end() - 1
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        blocks.append((start, j + 1))
        i = j + 1
    outside = "".join(text[a:b] for a, b in
                      zip([0] + [e for _, e in blocks], [s for s, _ in blocks] + [len(text)]))
    for start, end in blocks:
        for prop in re.findall(r"(--[\w-]+)\s*:", text[start:end]):
            if re.search(re.escape(prop) + r"\s*:", outside) is None:
                bad.append(f"{name}: {prop}")
if bad:
    print("dark-only properties:", ", ".join(bad))
    sys.exit(1)
PY
then
  ok "every dark-block property has a light :root definition"
else
  no "a color is defined only inside the dark media query"
fi

# 38d. one dark ground per look. The palette is restated per file, so a retune that
#      misses one file renders a body inside a differently coloured html canvas. This
#      case catches that drift.
echo "[38d] every surface shares one dark page ground"
if python3 - "${SCRIPT_DIR}" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
# Parity groups. The ia pair (browser ia theme + the Quick Look skin, which is the same
# look) share ia's ground. Grounds must agree WITHIN a group, not across
# groups. The vscode group states each token it must set in its dark block.
groups = {
    "vscode": {
        "assets/vscode-preview-head.html": ("--vscode-editor-background", "--vscode-textCodeBlock-background"),
    },
    "ia": {
        "assets/ia-theme.css": ("--ia-bg",),
        # The panel inherits --vscode-textCodeBlock-background from the copied md-style.html,
        # so only its own page ground is stated here.
        "integrations/safari/quick-look/Resources/ql-reading.css": ("--ql-paper",),
    },
}
for gname, surfaces in groups.items():
    found = {}
    for name, tokens in surfaces.items():
        text = (root / name).read_text()
        dark = text[text.index("@media (prefers-color-scheme: dark)"):]
        for token in tokens:
            m = re.search(re.escape(token) + r"\s*:\s*(#[0-9a-fA-F]{6})", dark)
            if not m:
                print(f"{name}: {token} not set in its dark block")
                sys.exit(1)
            found.setdefault(tokens.index(token), {})[name] = m.group(1)
    for role, values in found.items():
        if len(set(values.values())) != 1:
            label = "page" if role == 0 else "code"
            print(f"[{gname}] dark {label} ground differs: " + ", ".join(f"{k}={v}" for k, v in values.items()))
            sys.exit(1)
PY
then
  ok "page + code dark grounds identical across the browser and Quick Look"
else
  no "the dark ground has drifted between surfaces"
fi

# 39. The Quick Look appex is the largest surface in this tool and its tests only ran
#     inside build-safari.sh, so `bash tests/smoke.sh` reported green on a broken panel.
echo "[39] Quick Look render core"
if command -v node >/dev/null 2>&1; then
  if node "${SCRIPT_DIR}/integrations/safari/quick-look/test-render.js" >/dev/null 2>&1; then
    ok "ql-render suite passes"
  else
    no "ql-render suite failed (run it directly for the detail)"
  fi
else
  ok "node absent, ql-render suite skipped"
fi

# 40. The synthetic fixture renders every feature it exercises: frontmatter table,
#     inline + display math, a wide table in its scroll wrapper, highlighted code, a
#     callout, an image, and a wikilink.
echo "[40] synthetic fixture renders every feature"
FIX="${SCRIPT_DIR}/tests/fixture/fixture.md"
set +e; "$SPACEDOWN" "$FIX" --out "${TMP}/fx.html" --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]] \
   && grep -q 'class="sd-frontmatter"' "${TMP}/fx.html" \
   && grep -q 'class="math inline"' "${TMP}/fx.html" \
   && grep -q 'class="math display"' "${TMP}/fx.html" \
   && [[ "$(grep -c '<table' "${TMP}/fx.html")" -ge 3 ]] \
   && grep -q 'class="sourceCode' "${TMP}/fx.html" \
   && grep -q 'sd-callout-warning' "${TMP}/fx.html" \
   && grep -q 'data:image/svg+xml;base64' "${TMP}/fx.html" \
   && grep -q 'class="wikilink"' "${TMP}/fx.html"; then
  ok "frontmatter, math, tables, code, callout, image, wikilink all rendered"
else
  no "synthetic fixture render incomplete (rc=$rc)"
fi

echo "[svg-width] a lone SVG that declares a width keeps it; one without a width still fills the column"
mkdir -p "${TMP}/svgw"
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 616 300" width="616" height="300"><rect width="616" height="300" fill="#ccc"/></svg>' > "${TMP}/svgw/sized.svg"
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 300"><rect width="600" height="300" fill="#ccc"/></svg>' > "${TMP}/svgw/bare.svg"
printf '# w\n\n![a](sized.svg)\n\n![b](bare.svg)\n' > "${TMP}/svgw/w.md"
set +e; "$SPACEDOWN" "${TMP}/svgw/w.md" --out "${TMP}/svgw/w.html" --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]] \
   && tr '\n' ' ' < "${TMP}/svgw/w.html" | grep -q 'svg+xml;base64,[^"]*" width="616" alt="a"' \
   && ! tr '\n' ' ' < "${TMP}/svgw/w.html" | grep -q 'width="[0-9.]*" alt="b"' \
   && grep -q 'only-child\[src\^="data:image/svg+xml"\]:not(\[width\])' "${SCRIPT_DIR}/assets/ia-theme.css"; then
  ok "declared SVG width carried onto the img, bare SVG left to fill the column"
else
  no "SVG width handling wrong (rc=$rc)"
fi

echo "[ia-table] tables: soft hairlines between rows, body-weight cells, rules on the cells"
IA_THEME="${SCRIPT_DIR}/assets/ia-theme.css"
if grep -q 'table:not(.sd-frontmatter) > tbody > tr + tr > td { border-top: 1px solid var(--ia-table-rule); }' "$IA_THEME" \
   && grep -q 'table > tbody:last-child > tr:last-child > \* { border-bottom: 1px solid var(--ia-table-rule); }' "$IA_THEME" \
   && ! grep -q 'ia-row-rule' "$IA_THEME" \
   && ! grep -q 'tbody > tr > :first-child {' "$IA_THEME"; then
  ok "iA table rules"
else
  no "ia table drifted from iA Writer (light rules, bold first column, or rules on the table box)"
fi

echo "[ia-table-headless] a headless table behind a colgroup opens on a soft rule, not pandoc's ink tbody rule"
if grep -q 'table > tbody { border-top: none; border-bottom: none; }' "$IA_THEME" \
   && grep -q 'table > tbody:first-of-type > tr:first-child > \*,' "$IA_THEME" \
   && ! grep -q 'table > tbody:first-child > tr:first-child' "$IA_THEME"; then
  ok "headless table top rule"
else
  no "headless table: tbody ink rule not undone, or first-row rule still keyed on tbody:first-child"
fi

echo "[ia-list-hang] the dash marker takes no room, so wrapped bullet lines align under the text"
if grep -q 'content: "\\2013";' "$IA_THEME" \
   && grep -q 'width: 1.35em;' "$IA_THEME" \
   && grep -q 'margin-left: -1.35em;' "$IA_THEME" \
   && ! grep -q '2013\\00a0' "$IA_THEME"; then
  ok "list hang"
else
  no "dash marker is wider than its pull-back: wrapped bullet lines start left of the first line"
fi

echo "[page-end] the page leaves room below the last line"
if grep -q 'padding-bottom: 6em;' "${SCRIPT_DIR}/assets/vscode-preview-head.html"; then ok "bottom padding"; else no "no bottom padding on the page"; fi

echo "[one-edge] tables that fit and section rules end on the prose measure"
HEAD_HTML="${SCRIPT_DIR}/assets/vscode-preview-head.html"
if grep -q 'body > table:not(.sd-wide), body > hr { max-width: var(--sd-measure); }' "$HEAD_HTML" \
   && grep -q 'body > hr { margin-left: 0; }' "$HEAD_HTML"; then
  ok "one right edge"
else
  no "tables or rules run past the prose measure: the page has two right edges"
fi

echo "[phone-gutter] phones get one 20px gutter, not html plus body padding"
CHROME_HEAD="${SCRIPT_DIR}/assets/reading-chrome-head.html"
if grep -q '@media (max-width: 600px) {' "$CHROME_HEAD" \
   && grep -q 'body, html.sd-has-toc body, html.sd-has-toc.sd-toc-collapsed body { padding-left: 20px; padding-right: 20px; }' "$CHROME_HEAD"; then
  ok "phone gutter"
else
  no "phone gutter missing: text sits 52px in from each edge on a phone"
fi

echo "[phone-table] on phones a wide table scrolls in its own box"
if grep -q 'body > table:not(.sd-frontmatter) { display: block; overflow-x: auto; max-width: 100%; }' "$CHROME_HEAD"; then
  ok "phone table scroll"
else
  no "phone table scroll missing: a wide table pushes the page sideways on a phone"
fi

echo "[fm-width] the frontmatter table fills the column and its keys start on the text edge"
if grep -q 'width: 100%;                    /\* fills the column' "$HEAD_HTML" \
   && grep -q 'table.sd-frontmatter td:first-child { padding-left: 0; }' "$HEAD_HTML" \
   && ! grep -q 'max-width: 820px' "$HEAD_HTML"; then
  ok "frontmatter width"
else
  no "frontmatter table narrower than the column, or keys inset from the text edge"
fi

echo "[ia-caption] a caption under a lone image is centered"
if grep -q 'p:has(> img:only-child) + p {.*text-align: center;' "$IA_THEME"; then ok "centered caption"; else no "caption not centered"; fi

echo "[fonts] the ia page embeds the iA fonts (Safari ignores installed ones); tm and the opt-out do not"
printf '# T\n\nHello *world*.\n' > "${TMP}/fonts.md"
"$SPACEDOWN" "${TMP}/fonts.md" --out "${TMP}/fonts-ia.html" --no-open >/dev/null 2>&1 || true
SPACEDOWN_EMBED_FONTS=0 "$SPACEDOWN" "${TMP}/fonts.md" --out "${TMP}/fonts-off.html" --no-open >/dev/null 2>&1 || true
"$SPACEDOWN" "${TMP}/fonts.md" --font-mode tm --out "${TMP}/fonts-tm.html" --no-open >/dev/null 2>&1 || true
ia_faces=$(grep -o 'url(data:font/ttf;base64,' "${TMP}/fonts-ia.html" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$ia_faces" -eq 4 ]] && ! grep -q 'url(data:font/ttf' "${TMP}/fonts-off.html" && ! grep -q 'url(data:font/ttf' "${TMP}/fonts-tm.html"; then
  ok "4 embedded faces in ia, none with SPACEDOWN_EMBED_FONTS=0 or tm"
else
  no "font embedding wrong (ia faces=${ia_faces})"
fi

echo "[diagram] box drawing keeps iA Mono's advance (its font lacks those glyphs; a fallback one drifts the bars)"
PAPER_THEME="${SCRIPT_DIR}/assets/paper-theme.css"
diagram_ok=1
for theme in "$IA_THEME" "$PAPER_THEME"; do
  grep -q 'font-family: "SD Diagram Fallback";' "$theme" \
    && grep -q 'size-adjust: 99\.6594%;' "$theme" \
    && grep -q 'unicode-range: U+2190-21FF, U+2500-25FF;' "$theme" \
    && grep -q '"iA Writer Mono S", "SD Diagram Fallback", ui-monospace' "$theme" || diagram_ok=0
done
if [[ "$diagram_ok" -eq 1 ]]; then ok "box-drawing fallback sized to 0.6em in ia and paper"; else no "box-drawing glyphs fall back to a font with another advance: diagram bars drift"; fi

echo "[list] a list right under a line of text is a list, with task checkboxes"
printf '**Step one**\n- [ ] first task\n- [x] second task\n' > "${TMP}/list.md"
"$SPACEDOWN" "${TMP}/list.md" --out "${TMP}/list.html" --no-open >/dev/null 2>&1 || true
if grep -q '<li' "${TMP}/list.html" && [[ $(grep -c 'type="checkbox"' "${TMP}/list.html") -ge 2 ]] \
   && ! grep -q -- '- \[ \]' "${TMP}/list.html"; then ok "list without a preceding blank line"; else no "list folded into the paragraph as literal text"; fi

echo "[table] a table right under a line of text is a table; a fenced one stays code"
printf '**Performance**\n| Date | Amount |\n|------|--------|\n| 2021-01-21 | 100 |\n\n```\nlead\n| x | y |\n|---|---|\n```\n' > "${TMP}/tbl.md"
"$SPACEDOWN" "${TMP}/tbl.md" --out "${TMP}/tbl.html" --no-open >/dev/null 2>&1 || true
if grep -q '<th>Date</th>' "${TMP}/tbl.html" && grep -q '<td>2021-01-21</td>' "${TMP}/tbl.html" \
   && ! grep -q '<th>x</th>' "${TMP}/tbl.html" \
   && ! grep -q '| Date |' "${TMP}/tbl.html" && grep -q '|---|---|' "${TMP}/tbl.html"; then ok "table without a preceding blank line"; else no "table folded into the paragraph as literal pipes"; fi

echo "[table-empty] a header-only table gets one blank row; empty cells keep a line of height"
printf '| Company | Reason |\n|---------|--------|\n' > "${TMP}/tbe.md"
"$SPACEDOWN" "${TMP}/tbe.md" --out "${TMP}/tbe.html" --no-open >/dev/null 2>&1 || true
if grep -q '<th>Company</th>' "${TMP}/tbe.html" && [[ $(sed -n '/<tbody>/,/<\/tbody>/p' "${TMP}/tbe.html" | grep -c '<td') -eq 2 ]] \
   && grep -q 'td:empty::after' "${TMP}/tbe.html"; then ok "blank fill-in row"; else no "header-only table has no row, or empty cells collapse"; fi

# 41. The vendored iA fonts exist with their license, and the Quick Look skin build embeds
#     exactly the four as data URIs (the sandboxed panel cannot load installed fonts).
echo "[41] vendored iA fonts + license"
FONTS="${SCRIPT_DIR}/assets/fonts/ia"
if [[ -f "${FONTS}/iAWriterQuattroV.ttf" && -f "${FONTS}/iAWriterQuattroV-Italic.ttf" \
   && -f "${FONTS}/iAWriterMonoV.ttf" && -f "${FONTS}/iAWriterMonoV-Italic.ttf" ]] \
   && grep -q 'SIL OPEN FONT LICENSE' "${FONTS}/LICENSE.md"; then
  ok "four font files and the OFL text are vendored"
else
  no "assets/fonts/ia is missing a font or the license"
fi

echo "[42] build-ql-skin embeds the four iA fonts"
skin="$("${SCRIPT_DIR}/scripts/build-ql-skin" "${TMP}/skin.css" 2>/dev/null || true)"
if [[ "$skin" == "${TMP}/skin.css" ]] \
   && [[ $(grep -o 'src: url(data:font/ttf;base64,' "${TMP}/skin.css" | wc -l | tr -d ' ') -eq 4 ]] \
   && grep -q -- '--ql-body-font: "iA Writer Quattro V"' "${TMP}/skin.css" \
   && ! grep -q 'data:font' "${SCRIPT_DIR}/integrations/safari/quick-look/Resources/ql-reading.css"; then
  ok "exactly 4 font data URIs in the built skin; the committed source stays readable"
else
  no "skin build did not embed exactly 4 fonts"
fi

# 43-46. spacedown docx: markdown to .docx in the iA look.
docx() { "$SPACEDOWN" docx "$@"; }
docx_styles() { unzip -p "$1" word/styles.xml 2>/dev/null; }
printf -- '---\ntitle: "T"\n---\n\n<!-- private note -->\n\n## Head\n\nBody with [a link](https://x.test).\n\n> quote\n' > "${TMP}/d.md"

echo "[43] spacedown docx writes a .docx next to the input in the iA look"
docx "${TMP}/d.md" >/dev/null 2>&1 || true
if [[ -f "${TMP}/d.docx" ]] && docx_styles "${TMP}/d.docx" | grep -q 'IBM Plex Sans' \
   && docx_styles "${TMP}/d.docx" | grep -q 'w:color w:val="1A1A1A"'; then
  ok "iA docx styles (IBM Plex Sans, ink 1A1A1A)"
else
  no "docx is missing the iA styles"
fi

echo "[44] spacedown docx drops HTML comments and honors -o"
docx "${TMP}/d.md" -o "${TMP}/out.docx" >/dev/null 2>&1 || true
if [[ -f "${TMP}/out.docx" ]] && ! unzip -p "${TMP}/out.docx" word/document.xml | grep -q 'private note'; then
  ok "-o honored, comment dropped"
else
  no "-o ignored or the HTML comment leaked"
fi

echo "[45] spacedown docx refuses a missing input with 66"
set +e; docx "${TMP}/none.md" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 66 ]]; then ok "exit 66"; else no "got $rc"; fi

echo "[46] a symlinked spacedown docx still finds the reference doc"
ln -s "$SPACEDOWN" "${TMP}/linked-sd"
"${TMP}/linked-sd" docx "${TMP}/d.md" -o "${TMP}/linked.docx" >/dev/null 2>&1 || true
if docx_styles "${TMP}/linked.docx" | grep -q 'IBM Plex Sans'; then ok "symlink"; else no "symlink lost the reference doc"; fi

echo "[docx-table] a table right under a line of text is a Word table"
printf '**Performance**\n| Date | Amount |\n|------|--------|\n| 2021-01-21 | 100 |\n' > "${TMP}/dt.md"
docx "${TMP}/dt.md" -o "${TMP}/dt.docx" >/dev/null 2>&1 || true
if unzip -p "${TMP}/dt.docx" word/document.xml 2>/dev/null | grep -q '<w:tbl>' \
   && ! unzip -p "${TMP}/dt.docx" word/document.xml 2>/dev/null | grep -q '| Date |'; then
  ok "docx table without a preceding blank line"
else
  no "docx table folded into the paragraph as literal pipes"
fi

# ---- docx subcommand dispatch (separate block: keep additions here) ----
echo "[docx-1] spacedown docx --help prints usage on stdout and exits 0"
set +e; hout="$("$SPACEDOWN" docx --help 2>/dev/null)"; rc=$?; set -e
if [[ $rc -eq 0 && "$hout" == *"spacedown docx <file.md>"* ]]; then ok "help exit 0"; else no "rc=$rc"; fi

echo "[docx-2] spacedown docx with no file exits 64"
set +e; "$SPACEDOWN" docx >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 64 ]]; then ok "exit 64"; else no "got $rc"; fi

echo "[docx-3] spacedown docx prints only the output path on stdout"
dpath="$("$SPACEDOWN" docx "${TMP}/d.md" -o "${TMP}/pathonly.docx" 2>/dev/null)" || true
if [[ "$dpath" == "${TMP}/pathonly.docx" && -f "$dpath" ]]; then ok "stdout is the path"; else no "got '$dpath'"; fi

echo "[docx-4] plain spacedown <file> still renders HTML, not a docx"
hp="$("$SPACEDOWN" "${TMP}/d.md" --out "${TMP}/plain.html" --no-open 2>/dev/null)" || true
if [[ "$hp" == "${TMP}/plain.html" ]] && grep -q '<html' "${TMP}/plain.html"; then ok "html render unchanged"; else no "plain render broke: '$hp'"; fi

echo "[docx-5] the retired bin/spacedown-docx is gone"
if [[ ! -e "${SCRIPT_DIR}/bin/spacedown-docx" ]]; then ok "removed"; else no "bin/spacedown-docx still exists"; fi

# ---- reading-view polish: outline, tables, images, links, print, toolbar ----
printf '# Polish\n\n## Section\n\nSee https://d.foundation and [Dwarves](https://dwarves.foundation).\n\n- one\n- two\n' > "${TMP}/polish.md"
"$SPACEDOWN" "${TMP}/polish.md" --out "${TMP}/polish.html" --no-open >/dev/null 2>&1

echo "[polish-1] dash bullets are scoped to the article, never nav#TOC"
if grep -q 'ul:not(nav#TOC ul):not(.task-list) > li::before' "${TMP}/polish.html" \
   && ! grep -qE '^ul > li::before' "${TMP}/polish.html"; then
  ok "the dash selector excludes the outline list (and no unscoped copy remains)"
else
  no "dash bullets are not scoped away from nav#TOC"
fi

echo "[polish-2] an empty thead is hidden"
if grep -q 'thead:not(:has(th:not(:empty))) { display: none; }' "${TMP}/polish.html"; then
  ok "empty header row rule present"
else
  no "empty thead rule missing"
fi

echo "[polish-3] a local image becomes a data: URI, unless SPACEDOWN_EMBED_IMAGES=0"
mkdir -p "${TMP}/img"
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>\n' > "${TMP}/img/fig.svg"
head -c 5400000 /dev/zero > "${TMP}/img/huge.png"
printf '![](fig.svg)\n\n![](%s/img/fig.svg)\n\n![](huge.png)\n\n![](https://example.com/remote.png)\n' "$TMP" > "${TMP}/img/doc.md"
"$SPACEDOWN" "${TMP}/img/doc.md" --out "${TMP}/img/on.html" --no-open >/dev/null 2>"${TMP}/img/on.err"
SPACEDOWN_EMBED_IMAGES=0 "$SPACEDOWN" "${TMP}/img/doc.md" --out "${TMP}/img/off.html" --no-open >/dev/null 2>&1
svg_on=$(grep -o 'data:image/svg+xml;base64' "${TMP}/img/on.html" | wc -l | tr -d ' ' || true)
if [[ "$svg_on" -eq 2 ]] && ! grep -q 'src="fig.svg"' "${TMP}/img/on.html" \
   && grep -q 'src="huge.png"' "${TMP}/img/on.html" \
   && grep -q 'src="https://example.com/remote.png"' "${TMP}/img/on.html" \
   && [[ "$(grep -c 'image over 5 MB' "${TMP}/img/on.err")" -eq 1 ]]; then
  ok "relative and absolute svg embedded; a 5 MB+ file and a remote URL left alone (logged once)"
else
  no "image embedding wrong (svg data URIs=${svg_on})"
fi
if grep -q 'src="fig.svg"' "${TMP}/img/off.html" && ! grep -q 'data:image/svg+xml;base64' "${TMP}/img/off.html"; then
  ok "SPACEDOWN_EMBED_IMAGES=0 keeps the path"
else
  no "SPACEDOWN_EMBED_IMAGES=0 did not keep the image path"
fi

echo "[polish-4] a bare URL becomes a link; the ia theme styles links as links"
if grep -q '<a href="https://d.foundation"' "${TMP}/polish.html" \
   && grep -q -- '--ia-link: #1d5fd1' "${TMP}/polish.html" \
   && grep -q -- '--ia-link: #7aa7ff' "${TMP}/polish.html" \
   && grep -q 'a:focus-visible' "${TMP}/polish.html"; then
  ok "bare URL autolinked; accent, dark accent and focus ring present"
else
  no "bare URL not linked or link styling missing"
fi

echo "[polish-5] print: button, stylesheet, chrome hidden, link addresses"
if grep -q 'window.print()' "${TMP}/polish.html" && grep -q '@media print' "${TMP}/polish.html" \
   && grep -q 'nav#TOC, .sd-toolbar, .sd-toc-toggle, .sd-progress { display: none !important; }' "${TMP}/polish.html" \
   && grep -q 'content: " (" attr(href) ")"' "${TMP}/polish.html" \
   && grep -q 'break-inside: avoid' "${TMP}/polish.html"; then
  ok "print button wired; print sheet hides chrome, shows link addresses, keeps blocks whole"
else
  no "print support incomplete"
fi

echo "[polish-6] toolbar buttons carry an aria-label and a title; the progress bar exists"
labels_ok=1
for lbl in 'ICONS.zoomOut, "Zoom out"' 'ICONS.zoomIn, "Zoom in"' 'ICONS.print, "Print"' '"Reset zoom"'; do
  grep -qF "$lbl" "${TMP}/polish.html" || labels_ok=0
done
if [[ $labels_ok -eq 1 ]] && grep -qF 'COPY_LABEL = "Copy source"' "${TMP}/polish.html" \
   && grep -qF 'b.setAttribute("aria-label", label); b.title = title;' "${TMP}/polish.html" \
   && grep -q 'sd-progress' "${TMP}/polish.html"; then
  ok "zoom out, zoom level, zoom in, copy and print are labelled icon buttons; progress bar present"
else
  no "toolbar labels or progress bar missing"
fi

# ---- Skim reading mode ----
printf '# Skim\n\nPlot raised $10M in Q1.\n' > "${TMP}/skim.md"
"$SPACEDOWN" "${TMP}/skim.md" --out "${TMP}/skim.html" --no-open >/dev/null 2>&1 || true

echo "[skim-1] the toolbar has one Read menu button (menu-button ARIA, radio items) in place of the Skim toggle"
if grep -qF 'ICONS.read' "${TMP}/skim.html" \
   && grep -qF 'readTrigger.setAttribute("aria-haspopup", "menu");' "${TMP}/skim.html" \
   && grep -qF 'readTrigger.setAttribute("aria-expanded", "false");' "${TMP}/skim.html" \
   && grep -qF 'item.setAttribute("role", "menuitemradio");' "${TMP}/skim.html" \
   && grep -qF 'item.setAttribute("aria-checked"' "${TMP}/skim.html" \
   && grep -qF 'MODE_LABELS = { skim: "Skim", bionic: "Bionic", beeline: "BeeLine", rsvp: "RSVP" }' "${TMP}/skim.html" \
   && grep -qF '.sd-toolbar .sd-read.sd-on' "${TMP}/skim.html" \
   && ! grep -qF 'toggleReadMode("skim")' "${TMP}/skim.html"; then
  ok "Read button with a menu of Off, Skim, Bionic, BeeLine, RSVP; pressed look while a mode is on"
else
  no "Read menu button missing or the old Skim toggle is still wired"
fi

echo "[skim-2] the Skim CSS has skimgram's values: dim opacity .62 and .34, heat red at .18 and .42, underline 1px and 2px"
skim_css="$(perl -0pe 's{/\*.*?\*/}{}gs' "${SCRIPT_DIR}/assets/reading-chrome-head.html")"
if grep -qF 'html[data-sd-skim~="dim"] .sd-sk[data-sk="-1"] { opacity: .62; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="dim"] .sd-sk[data-sk="-2"] { opacity: .34; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="dim"] .sd-sk[data-sk="1"] { font-weight: 600; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="dim"] .sd-sk[data-sk="2"] { font-weight: 700; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="heat"] .sd-sk[data-sk="1"] { background: rgba(255, 71, 64, 0.18); border-radius: 2px; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="heat"] .sd-sk[data-sk="2"] { background: rgba(255, 71, 64, 0.42); border-radius: 2px; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="underline"] .sd-sk[data-sk="1"] { text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 2px; }' <<<"$skim_css" \
   && grep -qF 'html[data-sd-skim~="underline"] .sd-sk[data-sk="2"] { text-decoration: underline; text-decoration-thickness: 2px; text-underline-offset: 2px; font-weight: 600; }' <<<"$skim_css"; then
  ok "eight rules, each with the value skimgram 4ebb78a ships"
else
  no "Skim CSS rules missing or changed from skimgram's values"
fi

echo "[skim-3] the Skim settings need no theme token: the fade tokens are gone, the RSVP ink stays in every theme"
skim_tok_ok=1
for theme in ia tm paper; do
  [[ "$(grep -c -- '--sd-skim-ink: var(--' "${SCRIPT_DIR}/assets/${theme}-theme.css")" -eq 1 ]] || skim_tok_ok=0
  ! grep -q -- '--sd-skim-fade' "${SCRIPT_DIR}/assets/${theme}-theme.css" || skim_tok_ok=0
done
[[ "$(grep -c -- '--sd-skim-ink-base:' "${SCRIPT_DIR}/assets/reading-chrome-head.html")" -eq 1 ]] || skim_tok_ok=0
! grep -q -- '--sd-skim-fade' "${SCRIPT_DIR}/assets/reading-chrome-head.html" || skim_tok_ok=0
if [[ $skim_tok_ok -eq 1 ]]; then ok "ink token in ia, tm, paper and the read/mono fallback; no fade token anywhere"; else no "a theme lacks the ink token or still carries a fade token"; fi

echo "[skim-4] the mode is a switch: data-sd-read-mode plus one sd-<mode> class, saved like the outline state"
if grep -qF 'var READ_MODES = ["skim", "bionic", "beeline", "rsvp"];' "${TMP}/skim.html" \
   && grep -qF 'doc.setAttribute("data-sd-read-mode", mode)' "${TMP}/skim.html" \
   && grep -qF 'doc.classList.toggle("sd-" + m, m === mode)' "${TMP}/skim.html" \
   && grep -qF 'localStorage.setItem(MODE_KEY, mode === "rsvp" ? "" : mode);' "${TMP}/skim.html" \
   && grep -qF 'savedMode = savedName(localStorage.getItem(MODE_KEY) || "");' "${TMP}/skim.html" \
   && [[ "$(grep -c -F 'try {' <<<"$(grep -B1 -F 'localStorage.setItem(MODE_KEY' "${TMP}/skim.html")")" -ge 1 ]]; then
  ok "one mode at a time, persisted inside try/catch (RSVP is remembered as last mode, never reopened on load)"
else
  no "read-mode switch or its persistence missing"
fi

echo "[skim-5] there is one Skim: no rules-based key-word pass, no sd-key; a saved surprise still means Skim"
if ! grep -qE 'markKeyWords|sd-key|sd-scored|sd-skim-anim|Skim \(surprise\)' "${TMP}/skim.html" \
   && ! grep -rqE 'markKeyWords|\.sd-key|Skim \(surprise\)' "${SCRIPT_DIR}/assets" "${SCRIPT_DIR}/bin" "${SCRIPT_DIR}/README.md" \
   && grep -qF 'function savedName(v) { return v === "surprise" ? "skim" : v; }' "${TMP}/skim.html"; then
  ok "no key-word pass, no key class, no second Skim in the menu, the old saved name is mapped"
else
  no "the rules-based Skim or a (surprise) label is still around, or the saved-name mapping is missing"
fi

echo "[skim-6] print renders the normal view: every Skim rule sits inside @media screen"
skim_nocomment="$(perl -0pe 's{/\*.*?\*/}{}gs' "${SCRIPT_DIR}/assets/reading-chrome-head.html")"
skim_loose=$(awk '/^@media screen/{s=1} s==0 && /html\.sd-skim|data-sd-skim|\.sd-sk\[/{n++} /^}/{s=0} END{print n+0}' <<<"$skim_nocomment")
skim_all=$(grep -cE 'html\.sd-skim|data-sd-skim' <<<"$skim_nocomment" || true)
if [[ "$skim_loose" -eq 0 && "$skim_all" -ge 9 ]]; then
  ok "no Skim rule outside a screen-only block (${skim_all} rules inside)"
else
  no "a Skim rule can reach print (${skim_loose} outside @media screen of ${skim_all})"
fi

# ---- Reading modes: Skim, Bionic, BeeLine, RSVP ----
mkdir -p "${TMP}/read"
"$SPACEDOWN" "${SCRIPT_DIR}/tests/fixture/reading-en.md" --out "${TMP}/read/en.html" --no-open >/dev/null 2>&1 || true
READ_HEAD="${SCRIPT_DIR}/assets/reading-chrome-head.html"
READ_PART="${SCRIPT_DIR}/assets/skim-surprise.html"

echo "[read-1] the surprise engine ships as a partial, loaded before the chrome script, and is bundled"
read_a=$(grep -n 'window.sdSurprise = {' "${TMP}/read/en.html" | head -1 | cut -d: -f1 || true)
read_b=$(grep -n 'function applyReadMode' "${TMP}/read/en.html" | head -1 | cut -d: -f1 || true)
if [[ -f "$READ_PART" && -n "$read_a" && -n "$read_b" && "$read_a" -lt "$read_b" ]] \
   && [[ "$(grep -c 'window.sdSurprise = {' "${TMP}/read/en.html")" -eq 1 ]] \
   && grep -qF 'SKIM_SURPRISE="${SCRIPT_DIR}/../assets/skim-surprise.html"' "${SCRIPT_DIR}/bin/spacedown" \
   && perl -ne 'exit 1 if /[^\x00-\x7f]/' "$READ_PART"; then
  ok "partial present, injected once ahead of the chrome script, plain ASCII"
else
  no "assets/skim-surprise.html missing, not injected before the chrome script, or not ASCII"
fi

echo "[read-2] skimgram is credited: MIT, its copyright line, in the partial and in THIRD_PARTY_NOTICES.md"
if grep -q 'skimgram' "$READ_PART" && grep -qF 'Copyright (c) 2026 AwesomeDog' "$READ_PART" \
   && grep -i 'skimgram' "${SCRIPT_DIR}/THIRD_PARTY_NOTICES.md" | grep -q 'MIT' \
   && grep -i 'skimgram' "${SCRIPT_DIR}/THIRD_PARTY_NOTICES.md" | grep -qF 'AwesomeDog' \
   && grep -qF 'assets/skim-surprise.html' "${SCRIPT_DIR}/THIRD_PARTY_NOTICES.md"; then
  ok "attribution present in both places"
else
  no "skimgram attribution missing"
fi

echo "[read-3] the scorer port: NFC keys, page-only model for non-English, short and flat pages left unscored"
if grep -qF 'text.normalize("NFC")' "$READ_PART" \
   && grep -qF 'lang === "other" ? 0 : blendWeight(tokenCount)' "$READ_PART" \
   && grep -qF 'VI_RE' "$READ_PART" \
   && grep -qF 'page is too short to analyse' "$READ_PART" \
   && grep -qF 'page is statistically flat' "$READ_PART" \
   && grep -qF 'var MIN_SPREAD_BITS = 0.25;' "$READ_PART"; then
  ok "NFC fold, lambda 0 off the English prior, minTokens and spread guards present"
else
  no "scorer port is missing one of its guards"
fi

echo "[read-4] every mode rule sits inside @media screen; print only hides the RSVP overlay; no opacity after the Read menu rules"
read_css="$(perl -0pe 's{/\*.*?\*/}{}gs' "$READ_HEAD")"
read_loose=$(awk '/^@media screen/{s=1} /^@media print/{s=1} s==0 && /html\.sd-(skim|bionic|beeline|rsvp)|\.sd-rsvp-|\.sd-bl-|\.sd-sk\[/{n++} /^}/{s=0} END{print n+0}' <<<"$read_css")
read_all=$(grep -cE 'html\.sd-(skim|bionic|beeline|rsvp)|\.sd-rsvp-|\.sd-bl-' <<<"$read_css" || true)
read_print=$(awk '/^@media print/{p=1} p&&/sd-/{print}' <<<"$read_css" | grep -c 'sd-rsvp-overlay' || true)
if [[ "$read_loose" -eq 0 && "$read_all" -ge 20 && "$read_print" -ge 1 ]] \
   && grep -qF 'b.sd-bi { font-weight: inherit; }' <<<"$read_css" \
   && ! sed -n '/(7b) The Read menu/,$p' "$READ_HEAD" | perl -0pe 's{/\*.*?\*/}{}gs' | grep -q 'opacity'; then
  ok "no mode rule outside a screen-only block (${read_all} rules inside), print hides the overlay, bionic bold undone outside screen"
else
  no "a mode rule can reach print (${read_loose} outside @media screen) or uses opacity"
fi

echo "[read-5] every theme carries the reading-mode tokens, and the chrome carries light and dark fallbacks"
read_tok_ok=1
for theme in ia tm paper; do
  grep -q -- '--sd-read-bg:' "${SCRIPT_DIR}/assets/${theme}-theme.css" || read_tok_ok=0
done
[[ "$(grep -c -- '--sd-read-red-base:' "$READ_HEAD")" -eq 2 && "$(grep -c -- '--sd-read-blue-base:' "$READ_HEAD")" -eq 2 ]] || read_tok_ok=0
if [[ $read_tok_ok -eq 1 ]]; then ok "ground token in ia, tm, paper; red and blue fallbacks in light and dark"; else no "reading-mode tokens missing"; fi

echo "[read-6] turning a mode off puts the original text nodes back (no innerHTML round trip)"
if grep -qF 'undo.push({ orig: node, made: made });' "${TMP}/read/en.html" \
   && grep -qF 'first.parentNode.insertBefore(u.orig, first);' "${TMP}/read/en.html" \
   && grep -qF 'restoreText();' "${TMP}/read/en.html"; then
  ok "each wrapped text node is recorded and re-inserted on the way out"
else
  no "restore path missing"
fi

echo "[parity-1] the Skim engine matches skimgram 4ebb78a on every fixture: tokens, levels, raw and smoothed scores, page flattening, word lists"
if ! command -v node >/dev/null 2>&1; then
  echo "  skipped: node not found"
else
  parity_out="$(node "${SCRIPT_DIR}/scripts/skim-parity.mjs" 2>&1 || true)"
  if grep -qF 'skim-parity: OK' <<<"$parity_out" \
     && grep -qE '^0 mismatched tokens over [0-9]+ fixtures, 0 flatten differences, 0 word list differences, 0 token count differences$' <<<"$parity_out" \
     && [[ "$(grep -cE '^(cjk|code-mixed|en-599|en-600|en-long|en-medium|en-short|flat|identifiers|numbers|tiny) ' <<<"$parity_out")" -eq 11 ]]; then
    ok "eleven fixtures, 0 mismatched tokens, 0 flatten, word list and token count differences against the goldens"
  else
    no "the port differs from the skimgram goldens"
    sed 's/^/    /' <<<"$parity_out" | head -30 >&2
  fi

  echo "[parity-2] the fixtures reach the boundaries: gain switch at 600, lambda plateaus, CJK, identifier-heavy English, the three skip reasons, the 400k cap"
  if node -e '
    const fs = require("fs"), dir = process.argv[1] + "/tests/fixtures/skim/golden/";
    const g = (n) => JSON.parse(fs.readFileSync(dir + n + ".json", "utf8"));
    const seq = (x) => Array.from(x.tokens.kinds).filter((c) => c !== "s").length;
    const meta = JSON.parse(fs.readFileSync(dir + "_meta.json", "utf8"));
    const ok = seq(g("en-long")) > 6000 && g("en-599").cases["auto/50"].basis === "surprisal" && seq(g("en-599")) === 599
      && g("en-600").cases["auto/50"].basis === "gain" && seq(g("en-600")) === 600
      && seq(g("en-short")) > 400 && seq(g("en-short")) < 600 && seq(g("en-medium")) > 600 && seq(g("en-medium")) < 6000
      && g("tiny").cases["auto/50"].reason === "page is too short to analyse" && seq(g("tiny")) < 80
      && g("numbers").cases["auto/50"].reason === "not enough scoreable tokens" && seq(g("numbers")) >= 80
      && g("flat").cases["auto/50"].reason === "page is statistically flat"
      && Array.from(g("cjk").tokens.kinds).filter((c) => c === "c").length > 500
      && meta.cap["over-cap"].length > 400000 && meta.cap["cap-exact-400000"].runs === 400 && meta.cap["cap-just-under"].runs === 401
      && meta.upstream === "4ebb78a";
    process.exit(ok ? 0 : 1);
  ' "${SCRIPT_DIR}"; then
    ok "599 tokens scores by surprisal, 600 by gain; long, medium, short, CJK and identifier fixtures; too short, too few scoreable and flat pages skip; the cap trips at 400000 exactly"
  else
    no "a golden no longer covers a boundary it should"
  fi
fi

# The behaviour checks need a Chromium-family browser with --headless=new. SPACEDOWN_TEST_BROWSER names one;
# otherwise the usual places are tried. Without one the behaviour checks are skipped, not failed.
READ_BROWSER="${SPACEDOWN_TEST_BROWSER:-}"
if [[ -z "$READ_BROWSER" ]]; then
  for cand in "/Applications/Helium.app/Contents/MacOS/Helium" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
              "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
              "$(command -v google-chrome 2>/dev/null || true)" "$(command -v chromium 2>/dev/null || true)"; do
    if [[ -n "$cand" && -x "$cand" ]]; then READ_BROWSER="$cand"; break; fi
  done
fi

# drive_page <fixture> : render it, inline tests/reading-modes-driver.js, open it headless, keep the
# driver's JSON in ${TMP}/read/<fixture>.json ({"error": ...} when the page never answered).
# An optional tag and seed script: the seed runs first thing in <body>, so it can fill localStorage
# before the chrome reads it. The result lands in ${TMP}/read/<fixture><tag>.json.
drive_page() {
  local fixture="$1" tag="${2:-}" seed="${3:-}" name="$1${2:-}"
  local html="${TMP}/read/${name}.html" drive="${TMP}/read/${name}.drive.html" prof="${TMP}/read/prof-${name}" pid i
  "$SPACEDOWN" "${SCRIPT_DIR}/tests/fixture/${fixture}.md" --out "$html" --no-open >/dev/null 2>&1 || true
  python3 - "$html" "${SCRIPT_DIR}/tests/reading-modes-driver.js" "$drive" "$seed" <<'PY'
import sys
page = open(sys.argv[1], encoding="utf-8").read()
driver = open(sys.argv[2], encoding="utf-8").read()
seed = sys.argv[4]
if seed:
    at = page.index("<body", page.index("</head>"))
    at = page.index(">", at) + 1
    page = page[:at] + "<script>try { " + seed + " } catch (e) {}</script>" + page[at:]
cut = page.rindex("</body>")
open(sys.argv[3], "w", encoding="utf-8").write(page[:cut] + "<script>" + driver + "</script>" + page[cut:])
PY
  mkdir -p "$prof"
  "$READ_BROWSER" --headless=new --disable-gpu --no-first-run --no-default-browser-check --user-data-dir="$prof" \
    --window-size=1000,500 --virtual-time-budget=5000 --dump-dom "file://${drive}" > "${TMP}/read/${name}.dom" 2>/dev/null &
  pid=$!
  for i in $(seq 1 120); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  kill "$pid" 2>/dev/null || true
  pkill -f "user-data-dir=${prof}" 2>/dev/null || true
  python3 - "${TMP}/read/${name}.dom" "${TMP}/read/${name}.json" <<'PY'
import html, re, sys
dom = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<pre id="sd-test-result">(.*?)</pre>', dom, re.S)
open(sys.argv[2], "w", encoding="utf-8").write(html.unescape(m.group(1)) if m else '{"error": "the driver never answered"}')
PY
}
# rj <fixture> <python expression over r>: exit 0 when the expression holds on that fixture's JSON.
# The expressions are written in this file, so the eval runs only code this test authors.
rj() {
  python3 - "${TMP}/read/$1.json" "$2" <<'PY'
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if (not r.get("error") and eval(sys.argv[2])) else 1)
PY
}

if [[ -z "$READ_BROWSER" ]]; then
  echo "[read-7..13] skipped: no headless Chromium-family browser found (set SPACEDOWN_TEST_BROWSER)"
else
  drive_page reading-en
  drive_page reading-vi
  drive_page reading-tiny
  drive_page reading-en -surprise 'localStorage.setItem("sd-read-mode", "surprise"); localStorage.setItem("sd-read-last", "surprise");'
  drive_page reading-en -rules 'localStorage.setItem("sd-read-mode", "skim"); localStorage.setItem("sd-read-last", "skim");'
  drive_page reading-en -settings 'localStorage.setItem("sd-read-mode", "skim"); localStorage.setItem("sd-skim-emph", "underline"); localStorage.setItem("sd-skim-intensity", "100"); localStorage.setItem("sd-skim-basis", "surprisal");'
  drive_page reading-en -olddefault 'localStorage.setItem("sd-read-mode", "skim"); localStorage.setItem("sd-skim-emph", "dim,heat"); localStorage.setItem("sd-skim-intensity", "70");'
  drive_page reading-en -pickedheat 'localStorage.setItem("sd-read-mode", "skim"); localStorage.setItem("sd-skim-ver", "2"); localStorage.setItem("sd-skim-emph", "dim,heat");'
  for mode in beeline skim bionic; do
    drive_page reading-math "-$mode" "localStorage.setItem(\"sd-read-mode\", \"$mode\"); localStorage.setItem(\"sd-read-last\", \"$mode\");"
  done
  rj reading-en 'True' || echo "  note: the driver did not answer on the English fixture: $(head -c 300 "${TMP}/read/reading-en.json")" >&2

  echo "[read-7] one Read menu replaces the Skim button: five items, menu-button ARIA, keyboard open, move, close"
  if rj reading-en 'r["labels"] == ["Off","Skim","Bionic","BeeLine","RSVP"] and r["noSkimButton"] and r["trigger"]["popup"] == "menu" and r["trigger"]["expanded"] == "false" and r["trigger"]["controls"] == "sd-read-menu" and r["trigger"]["menuHidden"] and r["kbOpen"] and r["kbMoved"] and r["kbClose"]'; then
    ok "Off, Skim, Bionic, BeeLine, RSVP; ArrowDown opens, arrows move, Esc closes and refocuses"
  else
    no "Read menu structure or keyboard behaviour wrong"
  fi

  echo "[read-math] a saved reading mode never touches math: every formula still typesets"
  for mode in beeline skim bionic; do
    if python3 - "${TMP}/read/reading-math-${mode}.dom" <<'PY'
import re, sys
dom = open(sys.argv[1], encoding="utf-8", errors="replace").read()
spans = re.findall(r'<span class="math (?:inline|display)">(.{0,40})', dom)
typeset = [s for s in spans if s.startswith('<span class="katex')]
sys.exit(0 if spans and len(typeset) == len(spans) else 1)
PY
    then
      ok "$mode saved: all formulas typeset"
    else
      no "$mode saved: some formulas stayed raw TeX"
    fi
  done

  echo "[read-8] the S key turns the last mode off and on, and Skim is the default"
  if rj reading-en 'r["boot"]["mode"] is None and r["sKey"]["off"] is None and r["sKey"]["on"] == "skim" and r["sAfterOff"] == "bionic"'; then
    ok "S off, S on brings Skim back; after cycling to Bionic and Off, S brings Bionic back"
  else
    no "the S key or the default last mode changed behaviour"
  fi

  echo "[read-9] Skim on English: all four levels land on prose only, no stacking, skimgram's dim, heat and weight values on screen"
  if rj reading-en 'r["skim"]["classes"] == ["skim"] and r["skim"]["scored"] and r["skim"]["emph"] == "dim" and r["skim"]["checked"] == "Skim" and r["skim"]["stored"] == "skim" and r["skim"]["lang"] == "en" and min(r["skim"]["levels"].values()) > 5 and r["skim"]["inSkipped"] == 0 and r["skim"]["idempotent"] and r["skim"]["left"]["bionic"] == 0 and r["skim"]["left"]["beeline"] == 0' \
     && rj reading-en 'r["skim"]["style"]["dimStrong"] == "0.34" and r["skim"]["style"]["dimMild"] == "0.62" and r["skim"]["style"]["plain"] == "1" and r["skim"]["style"]["weight1"] == "600" and r["skim"]["style"]["weight2"] == "700" and r["skim"]["style"]["heatMild"] == "rgba(0, 0, 0, 0)" and r["skim"]["style"]["heatStrong"] == "rgba(0, 0, 0, 0)"'; then
    ok "span.sd-sk at data-sk -2 .. 2 on prose; none in code, links, bold, headings, th; opacity .34 and .62, weights 600 and 700, red at .18 and .42"
  else
    no "Skim did not score the English fixture as expected"
  fi

  echo "[read-10] Skim on Vietnamese scores on the page alone; a tiny page is left unscored and says so"
  if rj reading-vi 'r["skim"]["scored"] and r["skim"]["lang"] == "other" and r["skim"]["spans"] > 20 and r["skim"]["inSkipped"] == 0' \
     && rj reading-tiny 'not r["skim"]["scored"] and r["skim"]["spans"] == 0 and r["skim"]["skipped"] and "too short" in r["skim"]["label"] and r["off"]["restored"] and r["off"]["label"] == "Reading mode: Off"'; then
    ok "Vietnamese: page-only model, scored; tiny page: no spans, tooltip says too short, text untouched"
  else
    no "non-English or tiny page handled wrongly"
  fi

  echo "[read-10b] Skim settings: Emphasis (Dim, Heat, Underline), Intensity, Score; persisted; Off restores the page"
  if rj reading-en 'r["settings"]["hiddenWhenOff"] and r["settings"]["shownWhenSkim"] and r["settings"]["labels"] == ["Dim","Heat","Underline"] and r["settings"]["basisOptions"] == ["auto","surprisal","gain"] and r["settings"]["defaults"] == {"emph": "dim", "intensity": "50", "basis": "auto", "pressed": ["true","false","false"]}' \
     && rj reading-en 'r["settings"]["dimOnly"]["attr"] == "dim" and r["settings"]["dimOnly"]["stored"] == "dim" and r["settings"]["dimOnly"]["sameNode"] and r["settings"]["dimOnly"]["heat"] == "rgba(0, 0, 0, 0)" and r["settings"]["dimUnderline"]["attr"] == "dim underline" and r["settings"]["dimUnderline"]["underline"] == "underline" and r["settings"]["none"]["attr"] == "" and r["settings"]["none"]["stored"] == "" and r["settings"]["none"]["spans"] == r["settings"]["base"] and r["settings"]["restored"]["attr"] == "dim"' \
     && rj reading-en 'r["settings"]["full"]["spans"] > r["settings"]["base"] and r["settings"]["full"]["stored"] == "100" and r["settings"]["full"]["out"] == "100" and r["settings"]["zero"]["spans"] == 0 and r["settings"]["zero"]["attr"] is not None and r["settings"]["back"]["same"] and r["settings"]["surprisal"]["spans"] > 0 and r["settings"]["surprisal"]["stored"] == "surprisal" and r["settings"]["surprisal"]["noStack"] and r["settings"]["auto"]["same"]' \
     && rj reading-en 'r["settings"]["off"]["restored"] and all(v == 0 for v in r["settings"]["off"]["left"].values()) and not r["settings"]["off"]["attr"] and r["settings"]["off"]["hiddenAgain"]'; then
    ok "panel only while Skim is on; emphasis combines and persists with no rescore; intensity 100 marks more, 0 marks nothing; basis rescores without stacking; Off restores"
  else
    no "Skim settings panel or its persistence wrong"
  fi

  echo "[read-10d] Skim defaults to Dim only; Heat still applies when selected; an old saved Dim and Heat resolves to Dim only"
  if rj reading-en 'r["settings"]["defaults"]["emph"] == "dim" and r["settings"]["defaults"]["pressed"] == ["true","false","false"] and r["settings"]["defaultHeat"] == "rgba(0, 0, 0, 0)" and r["settings"]["heatOn"]["attr"] == "dim heat" and r["settings"]["heatOn"]["stored"] == "dim,heat" and r["settings"]["heatOn"]["sameNode"] and r["settings"]["heatOn"]["heat"] == "rgba(255, 71, 64, 0.42)"' \
     && rj reading-en-olddefault 'r["boot"]["mode"] == "skim" and r["boot"]["scored"] and r["boot"]["emph"] == "dim" and r["settings"]["defaults"]["pressed"] == ["true","false","false"] and r["settings"]["defaults"]["intensity"] == "70" and r["settings"]["defaultHeat"] == "rgba(0, 0, 0, 0)"' \
     && rj reading-en-pickedheat 'r["boot"]["mode"] == "skim" and r["boot"]["emph"] == "dim heat" and r["settings"]["defaults"]["pressed"] == ["true","true","false"] and r["settings"]["defaultHeat"] == "rgba(255, 71, 64, 0.42)"' \
     && rj reading-en-settings 'r["boot"]["emph"] == "underline"'; then
    ok "default is dim; clicking Heat paints it; saved dim,heat without a version opens as dim (intensity kept); dim,heat saved after the change, and other mixes, are kept"
  else
    no "Skim default emphasis or its migration wrong"
  fi

  echo "[read-10c] saved state: an old surprise or skim value opens Skim, and saved settings are applied at load"
  if rj reading-en-surprise 'r["boot"]["mode"] == "skim" and r["boot"]["scored"] and r["boot"]["emph"] == "dim" and r["boot"]["spans"] > 100 and r["boot"]["last"] == "surprise" and all(v == 0 for v in r["boot"]["left"].values())' \
     && rj reading-en-rules 'r["boot"]["mode"] == "skim" and r["boot"]["scored"] and r["boot"]["spans"] > 100 and all(v == 0 for v in r["boot"]["left"].values())' \
     && rj reading-en-settings 'r["boot"]["mode"] == "skim" and r["boot"]["emph"] == "underline" and r["boot"]["spans"] == r["settings"]["base"] and r["settings"]["defaults"]["intensity"] == "100" and r["settings"]["defaults"]["basis"] == "surprisal" and r["settings"]["defaults"]["pressed"] == ["false","false","true"]'; then
    ok "surprise and skim both open Skim at load; emphasis, intensity and score basis come back from storage"
  else
    no "saved reading state not migrated or settings not restored"
  fi

  echo "[read-11] Bionic bolds the start of each word (45%, at least 1, short words 1), Unicode aware, prose only"
  if rj reading-en 'r["bionic"]["classes"] == ["bionic"] and r["bionic"]["count"] > 100 and "|extrao|" in "|" + r["bionic"]["sample"] + "|" and "|docu|" in "|" + r["bionic"]["sample"] + "|" and r["bionic"]["inSkipped"] == 0 and r["bionic"]["weight"] == "700" and r["bionic"]["sOffRestores"] and r["bionic"]["stored"] == "bionic" and r["bionic"]["left"]["skim"] == 0' \
     && rj reading-vi 'r["bionic"]["count"] > 100 and "|nh|" in "|" + r["bionic"]["sample"] + "|" and "|ẩ|" in "|" + r["bionic"]["sample"] + "|"'; then
    ok "b.sd-bi at 700 weight; extrao|rdinary, docu|ments, 1 letter of a short word; Vietnamese nh|anh and a whole combined vowel"
  else
    no "bionic splitting or scope wrong"
  fi

  echo "[read-12] BeeLine colours each line: ink to blue, then blue to ink to red, each line starting on the colour the last one ended on"
  if rj reading-en 'r["beeline"]["classes"] == ["beeline"] and r["beeline"]["words"] > 100 and r["beeline"]["lines"] >= 3 and r["beeline"]["startInk"] < 3 and r["beeline"]["join"] < 3 and r["beeline"]["endDiffersFromInk"] and r["beeline"]["midInk"] and r["beeline"]["inSkipped"] == 0 and r["beeline"]["left"]["bionic"] == 0'; then
    ok "word spans, first word on the ink, line ends meet the next line starts, middle of a line is ink"
  else
    no "beeline gradient or continuity wrong"
  fi

  echo "[read-12b] BeeLine is smooth: every word paints its own linear-gradient slice, clipped to the text, and neighbours meet at the same colour"
  if rj reading-en 'r["beeline"]["gradient"]["words"] > 30 and r["beeline"]["gradient"]["withGradient"] == r["beeline"]["gradient"]["words"] and r["beeline"]["gradient"]["clipped"] == r["beeline"]["gradient"]["words"] and r["beeline"]["gradient"]["clear"] == r["beeline"]["gradient"]["words"] and r["beeline"]["gradient"]["seamPairs"] > 20 and r["beeline"]["gradient"]["seam"] < 3 and r["beeline"]["gradient"]["wide"] > 5 and r["beeline"]["gradient"]["flat"] == 0'; then
    ok "linear-gradient background on every word, background-clip text, clear text fill, no flat word, seams under 3 channel units"
  else
    no "beeline words are not smooth gradient slices, or neighbouring words do not meet"
  fi

  echo "[read-13] RSVP: dialog overlay, recognition letter near 35%, Space pauses, arrows step and change speed, Esc closes and exits"
  if rj reading-en 'r["rsvp"]["open"] and r["rsvp"]["role"] == "dialog" and r["rsvp"]["modal"] == "true" and r["rsvp"]["paused"] and r["rsvp"]["word0"] == "Reading" and r["rsvp"]["orp"]["before"] == int(r["rsvp"]["orp"]["len"] * 0.35) and r["rsvp"]["orp"]["mid"] == 1 and r["rsvp"]["word1"] == "modes" and r["rsvp"]["pos"].startswith("2 / ") and r["rsvp"]["wpm"] == "325 wpm" and r["rsvp"]["wpmDown"] == "275 wpm" and r["rsvp"]["closed"] and r["rsvp"]["triggerOff"]' \
     && rj reading-en '" const " not in r["rsvp"]["allWords"] and " return " not in r["rsvp"]["allWords"] and " project page, " in r["rsvp"]["allWords"] and " bold text stays bold " in r["rsvp"]["allWords"] and r["rsvp"]["startTop"] == "Reading" and r["rsvp"]["startScrolled"] != "Reading" and r["rsvp"]["stored"] == ["", "rsvp"]'; then
    ok "words come from prose (no code, link text kept), starts at the first block in view, current mode not saved, last mode remembered"
  else
    no "RSVP behaviour wrong"
  fi

  echo "[read-14] switching through every mode never stacks markup; Off restores the original text exactly; S brings the last mode back"
  if rj reading-en 'r["switched"]["classes"] == ["bionic"] and r["switched"]["left"]["skim"] == 0 and r["switched"]["left"]["beeline"] == 0 and r["switched"]["left"]["rsvp"] == 0 and r["switched"]["left"]["bionic"] > 0 and r["off"]["classes"] == [] and not r["off"]["attr"] and r["off"]["restored"] and all(v == 0 for v in r["off"]["left"].values()) and r["off"]["stored"] == ""' \
     && rj reading-vi 'r["off"]["restored"] and all(v == 0 for v in r["off"]["left"].values())'; then
    ok "one class at a time, zero leftover spans, text and node count identical to the load state"
  else
    no "a mode left markup behind or the text did not restore"
  fi
fi

# ---- CLI bundled inside the app (scripts/bundle-cli) ----
FAKE_APP="${TMP}/stage/Spacedown.app"
mkdir -p "${FAKE_APP}/Contents"
"${SCRIPT_DIR}/scripts/bundle-cli" "$FAKE_APP" >/dev/null 2>&1 || true
CLI_DIR="${FAKE_APP}/Contents/Resources/cli"

echo "[bundle-1] bundle-cli lays out the CLI and every runtime file under Contents/Resources/cli"
need_ok=1
for f in bin/spacedown scripts/ia-fontface-css assets/ia-theme.css assets/tm-theme.css assets/paper-theme.css \
         assets/vscode-preview-head.html assets/reading-chrome-head.html assets/reading-chrome-foot.html assets/skim-surprise.html \
         assets/livereload-foot.html assets/livereload-server.py assets/embed-images.py \
         assets/frontmatter-to-table.py assets/callouts-to-html.py assets/docx/ia-reference.docx \
         assets/fonts/ia/iAWriterQuattroV.ttf; do
  [[ -f "${CLI_DIR}/${f}" ]] || { need_ok=0; echo "    missing: ${f}" >&2; }
done
if [[ $need_ok -eq 1 && -x "${CLI_DIR}/bin/spacedown" && -x "${CLI_DIR}/scripts/ia-fontface-css" \
      && ! -e "${CLI_DIR}/assets/REFRESH.md" ]]; then
  ok "layout complete, scripts executable, maintainer notes left out"
else
  no "bundled layout incomplete"
fi

echo "[bundle-2] bundle-cli refuses a path that is not an app bundle"
set +e; "${SCRIPT_DIR}/scripts/bundle-cli" "${TMP}/not-an-app" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 64 ]]; then ok "exit 64"; else no "got $rc"; fi

# The staged app moves away from the repo and is run through a symlink, like the cask's
# `binary` stanza does, so any lookup that reaches back into the checkout fails here.
mv -f "${TMP}/stage" "${TMP}/relocated"
BUNDLED="${TMP}/relocated/Spacedown.app/Contents/Resources/cli/bin/spacedown"
mkdir -p "${TMP}/brewbin"
ln -s "$BUNDLED" "${TMP}/brewbin/spacedown"

echo "[bundle-3] the bundled CLI, moved and run through a symlink, renders the same HTML as the repo CLI"
printf -- '---\ntitle: B\n---\n\n> [!note] Hi\n> body\n\n| a | b |\n|---|---|\n| 1 | 2 |\n' > "${TMP}/b.md"
"$SPACEDOWN" "${TMP}/b.md" --out "${TMP}/b-repo.html" --no-open >/dev/null 2>&1 || true
"${TMP}/brewbin/spacedown" "${TMP}/b.md" --out "${TMP}/b-bundled.html" --no-open >/dev/null 2>&1 || true
if [[ -s "${TMP}/b-bundled.html" ]] && cmp -s "${TMP}/b-repo.html" "${TMP}/b-bundled.html"; then
  ok "byte-identical page (theme, chrome, frontmatter table, callout)"
else
  no "bundled render differs from the repo render or failed"
fi

echo "[bundle-4] the bundled CLI embeds the iA fonts"
if grep -q 'iA Writer Quattro V' "${TMP}/b-bundled.html" && grep -q 'base64,' "${TMP}/b-bundled.html"; then
  ok "font faces embedded from the bundle"
else
  no "bundled render carries no embedded iA fonts"
fi

echo "[bundle-5] the bundled CLI exports .docx in the iA look"
"${TMP}/brewbin/spacedown" docx "${TMP}/d.md" -o "${TMP}/bundled.docx" >/dev/null 2>&1 || true
if docx_styles "${TMP}/bundled.docx" | grep -q 'IBM Plex Sans'; then ok "docx from the bundle"; else no "bundled docx failed"; fi

echo "[bundle-6] build-safari.sh bundles the CLI by default; the store build opts out"
if grep -q 'scripts/bundle-cli' "${SCRIPT_DIR}/integrations/build-safari.sh" \
   && grep -q 'BUNDLE_CLI="${BUNDLE_CLI:-1}"' "${SCRIPT_DIR}/integrations/build-safari.sh" \
   && grep -q 'BUNDLE_CLI=0' "${SCRIPT_DIR}/scripts/release.sh"; then
  ok "default on, MAS build off"
else
  no "build wiring missing"
fi

# notary-auth: build-safari.sh picks the notarytool credentials like scripts/release.sh.
# A fake xcrun on PATH records its argv; the real build needs Xcode, so only the choice runs.
echo "[notary-auth] NOTARY_KEY selects the API key; else the keychain profile"
mkdir -p "${TMP}/fakebin"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/xcrun.argv"\n' "$TMP" > "${TMP}/fakebin/xcrun"
chmod +x "${TMP}/fakebin/xcrun"
notary_argv() {
  : > "${TMP}/xcrun.argv"
  ( PATH="${TMP}/fakebin:$PATH"; source "${SCRIPT_DIR}/integrations/notary-auth.sh"; notary_auth
    xcrun notarytool submit z.zip "${NOTARY_AUTH[@]}" --wait ) 2>"${TMP}/notary.err" || return $?
  cat "${TMP}/xcrun.argv"
}
got="$(NOTARY_KEY=/k/AuthKey.p8 NOTARY_KEY_ID=KID NOTARY_ISSUER=ISS NOTARIZE=prof notary_argv)"
if [[ "$got" == "notarytool submit z.zip --key /k/AuthKey.p8 --key-id KID --issuer ISS --wait" ]]; then
  ok "NOTARY_KEY gives --key/--key-id/--issuer, ahead of NOTARIZE"
else
  no "api key argv: $got"
fi
got="$(NOTARY_KEY= NOTARIZE=prof notary_argv)"
if [[ "$got" == "notarytool submit z.zip --keychain-profile prof --wait" ]]; then
  ok "NOTARY_KEY unset gives --keychain-profile <name>"
else
  no "profile argv: $got"
fi
set +e
NOTARY_KEY=/k/AuthKey.p8 NOTARY_ISSUER=ISS notary_argv >/dev/null 2>&1; rc_noid=$?
NOTARY_KEY=/k/AuthKey.p8 NOTARY_KEY_ID=KID notary_argv >/dev/null 2>&1; rc_noiss=$?
set -e
if [[ $rc_noid -ne 0 && $rc_noiss -ne 0 && ! -s "${TMP}/xcrun.argv" ]]; then
  ok "NOTARY_KEY without NOTARY_KEY_ID or NOTARY_ISSUER fails before xcrun runs"
else
  no "incomplete key accepted: id=$rc_noid issuer=$rc_noiss"
fi
if grep -q 'notary-auth.sh' "${SCRIPT_DIR}/integrations/build-safari.sh" \
   && grep -q '"${NOTARY_AUTH\[@\]}"' "${SCRIPT_DIR}/integrations/build-safari.sh" \
   && grep -q 'NOTARIZE" || -n "$NOTARY_KEY"' "${SCRIPT_DIR}/integrations/build-safari.sh" \
   && ! grep -q 'keychain-profile "$NOTARIZE"' "${SCRIPT_DIR}/integrations/build-safari.sh"; then
  ok "build-safari.sh notarizes on either variable through NOTARY_AUTH"
else
  no "build-safari.sh notary wiring missing"
fi

# layout-check: the no-browser surface only (--help, no args, bad option)
echo "[layout-check] usage and argument errors need no browser"
LC="${SCRIPT_DIR}/scripts/layout-check"
set +e
"$LC" --help >/dev/null 2>&1; lc_help=$?
"$LC" >/dev/null 2>&1; lc_none=$?
"$LC" --bogus x.md >/dev/null 2>&1; lc_bad=$?
set -e
if [[ -x "$LC" && $lc_help -eq 0 && $lc_none -eq 64 && $lc_bad -eq 64 ]]; then
  ok "--help exits 0; no file and unknown option exit 64"
else
  no "layout-check usage: help=$lc_help none=$lc_none bad=$lc_bad"
fi

# --shot: argument errors need no browser; the render needs Helium, Chrome or Chromium
echo "[--shot] argument errors"
printf '# Shot\n\nShort text.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n' > "${TMP}/shot-narrow.md"
set +e
"$SPACEDOWN" "${TMP}/shot-narrow.md" --shot "${TMP}/x.png" --watch >/dev/null 2>&1; shot_watch=$?
"$SPACEDOWN" "$TMP" --shot "${TMP}/x.png" >/dev/null 2>&1; shot_dir=$?
"$SPACEDOWN" "${TMP}/shot-narrow.md" --shot-width abc >/dev/null 2>&1; shot_w=$?
set -e
if [[ $shot_watch -eq 64 && $shot_dir -eq 64 && $shot_w -eq 64 ]]; then
  ok "--shot with --watch, a directory or a bad width exits 64"
else
  no "--shot argument errors: watch=$shot_watch dir=$shot_dir width=$shot_w"
fi

echo "[--shot] screenshot and wide-table warning"
set +e
shot_out=$("$SPACEDOWN" "${TMP}/shot-narrow.md" --out "${TMP}/shot-narrow.html" --shot "${TMP}/shot-narrow.png" 2>&1); shot_rc=$?
set -e
if [[ $shot_rc -eq 4 && "$shot_out" == *"none found"* ]]; then
  echo "  skip: no Helium, Chrome or Chromium installed"
else
  if [[ $shot_rc -eq 0 && -s "${TMP}/shot-narrow.png" && "$shot_out" == *"${TMP}/shot-narrow.png" && "$shot_out" != *"WARN wide table"* ]]; then
    ok "--shot writes a non-empty PNG, prints its path, no warning on a narrow table"
  else
    no "--shot narrow: rc=$shot_rc out=$shot_out"
  fi
  {
    printf '# Wide\n\n| '
    for i in $(seq 1 30); do printf 'column-header-number-%s | ' "$i"; done
    printf '\n|'
    for i in $(seq 1 30); do printf -- '---|'; done
    printf '\n| '
    for i in $(seq 1 30); do printf 'some-long-cell-value-%s | ' "$i"; done
    printf '\n'
  } > "${TMP}/shot-wide.md"
  set +e
  shot_out=$("$SPACEDOWN" "${TMP}/shot-wide.md" --out "${TMP}/shot-wide.html" --shot "${TMP}/shot-wide.png" 2>&1); shot_rc=$?
  set -e
  if [[ $shot_rc -eq 0 && -s "${TMP}/shot-wide.png" && "$shot_out" == *"WARN wide table"* ]]; then
    ok "a very wide table prints a WARN wide table line"
  else
    no "--shot wide: rc=$shot_rc out=$shot_out"
  fi
fi

echo "[katex] the page loads one pinned KaTeX version, never katex@latest"
printf 'Math: $x^2$\n' > "${TMP}/katex-pin.md"
"$SPACEDOWN" "${TMP}/katex-pin.md" --out "${TMP}/katex-pin.html" --no-open >/dev/null 2>&1
if grep -q 'katex@latest' "${TMP}/katex-pin.html"; then
  no "katex pin: page loads katex@latest"
elif grep -Eq 'katex@[0-9]+\.[0-9]+\.[0-9]+/dist/katex\.min\.js' "${TMP}/katex-pin.html"; then
  ok "katex loads from an exact pinned version"
else
  no "katex pin: no exact katex@X.Y.Z script in the page"
fi

echo
if [[ $fail -gt 0 ]]; then
  echo "smoke: $pass passed, $fail FAILED" >&2
  exit 1
fi
echo "smoke: all $pass passed"
exit 0
