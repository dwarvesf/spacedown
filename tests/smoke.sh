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

# 11. VSCodium / VS Code preview stylesheet injected into the page head
echo "[11] vscode preview style injected"
if grep -q 'VSCodium / VS Code' "${TMP}/fixture.html"; then ok "vscode style head present"; else no "vscode style head missing"; fi

# 12. no centered pandoc title-header block (VS Code preview never shows one)
echo "[12] no title-header block"
if grep -q 'class="title"' "${TMP}/fixture.html"; then no "title block present"; else ok "no title block"; fi

# 13. page column overrides pandoc's 36em default (designer pass 2026-07-12: the old
#     body-wide `max-width: none` became a 60rem page column + 48rem prose measure).
#     The 60rem body rule must appear AFTER pandoc's 36em so the cascade lets it win.
echo "[13] page column overrides pandoc default"
line36=$(grep -n 'max-width: 36em' "${TMP}/fixture.html" | head -1 | cut -d: -f1)
line60=$(grep -n 'max-width: 60rem' "${TMP}/fixture.html" | head -1 | cut -d: -f1)
if [[ -n "$line60" ]] && { [[ -z "$line36" ]] || [[ "$line60" -gt "$line36" ]]; } \
   && grep -q 'max-width: 48rem' "${TMP}/fixture.html"; then
  ok "60rem page column wins over pandoc 36em; 48rem prose measure present"
else
  no "page column / prose measure missing or ordered before pandoc default"
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

# 17e. The default renders the paper theme, --font-mode=paper matches it, and
#      --font-mode=mono carries no paper tokens (negative control).
echo "[17e] font-mode paper default"
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode=paper --out "${TMP}/paper.html" --no-open >/dev/null 2>&1
"$SPACEDOWN" "${TMP}/fixture.md" --font-mode=mono --out "${TMP}/mono.html" --no-open >/dev/null 2>&1
if grep -q -- '--paper-bg' "${TMP}/default.html" \
   && grep -q -- '--paper-bg' "${TMP}/paper.html" \
   && ! grep -q -- '--paper-bg' "${TMP}/mono.html" && ! grep -q -- '--paper-bg' "${TMP}/read.html"; then
  ok "default renders paper; mono and read unaffected (negative control)"
else
  no "paper default not behaving"
fi

# 17f. an unknown font mode is a usage error
echo "[17f] unknown font mode -> exit 64"
set +e; "$SPACEDOWN" "${TMP}/fixture.md" --font-mode=nope --no-open >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 64 ]]; then ok "exit 64"; else no "got $rc"; fi

# 17g. SPACEDOWN_THEME_CSS replaces the paper theme; read mode ignores it; a missing
#      file is a usage error.
echo "[17g] SPACEDOWN_THEME_CSS theme hook"
printf ':root { --custom-theme-bg: #123456; }\n' > "${TMP}/custom.css"
SPACEDOWN_THEME_CSS="${TMP}/custom.css" "$SPACEDOWN" "${TMP}/fixture.md" --out "${TMP}/custom.html" --no-open >/dev/null 2>&1
SPACEDOWN_THEME_CSS="${TMP}/custom.css" "$SPACEDOWN" "${TMP}/fixture.md" --font-mode=read --out "${TMP}/custom-read.html" --no-open >/dev/null 2>&1
set +e; SPACEDOWN_THEME_CSS="${TMP}/nope.css" "$SPACEDOWN" "${TMP}/fixture.md" --no-open >/dev/null 2>&1; rc=$?; set -e
if grep -q -- '--custom-theme-bg' "${TMP}/custom.html" && ! grep -q -- '--paper-bg' "${TMP}/custom.html" \
   && ! grep -q -- '--custom-theme-bg' "${TMP}/custom-read.html" && [[ $rc -eq 64 ]]; then
  ok "theme file replaces paper; read unaffected; missing file exits 64"
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
echo "[38c] no color defined only inside a dark media query"
if python3 - "${SCRIPT_DIR}/assets" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
bad = []
for name in ("vscode-preview-head.html", "reading-chrome-head.html", "paper-theme.css"):
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
# Parity groups. The paper pair (browser paper theme + the Quick Look skin, which is
# the same look) share paper's ground. Grounds must agree WITHIN a group, not across
# groups. The vscode group states each token it must set in its dark block.
groups = {
    "vscode": {
        "assets/vscode-preview-head.html": ("--vscode-editor-background", "--vscode-textCodeBlock-background"),
    },
    "paper": {
        "assets/paper-theme.css": ("--paper-bg",),
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
   && grep -q '<img src="chart.svg"' "${TMP}/fx.html" \
   && grep -q 'class="wikilink"' "${TMP}/fx.html"; then
  ok "frontmatter, math, tables, code, callout, image, wikilink all rendered"
else
  no "synthetic fixture render incomplete (rc=$rc)"
fi

echo
if [[ $fail -gt 0 ]]; then
  echo "smoke: $pass passed, $fail FAILED" >&2
  exit 1
fi
echo "smoke: all $pass passed"
exit 0
