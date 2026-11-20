# assets/ provenance

`vscode-preview-head.html` makes spacedown's HTML look like VSCodium / VS Code's
built-in markdown preview pane. It is injected into the page `<head>` (last, so it
wins over pandoc's default template) via `pandoc --include-in-header`.

## What's in it

One `<style>` block, in five parts:

1. **Theme variables**, concrete "Light Modern" values for the `--vscode-*` / `--markdown-*`
   custom properties that upstream `markdown.css` references but does not define (those are
   normally injected by the VS Code webview host).
2. **Base overrides**, neutralize pandoc's default template (`max-width: 36em`, `margin: auto`,
   `#fdfdfd` background) so the page is full-width with VS Code's 26px side padding.
3. **Inline-code chip**, `markdown.css` styles only block code; VS Code's theme paints inline
   `<code>`. Approximated with a subtle light chip.
4. **Upstream `markdown.css` (verbatim)**, the real VS Code stylesheet, kept byte-for-byte so it
   can be re-pulled cleanly.
5. **Unscoped light border colors**, upstream scopes h1/h2/hr/td/th border colors under a
   `.vscode-light` class that the standalone body doesn't carry, so they are re-asserted unscoped.

Math is rendered by KaTeX (pandoc `--katex`), which is exactly what VS Code uses, so math fidelity
comes for free and needs no CSS here.

## Fonts are NOT baked here

The font values in part 1 (`--markdown-font-family`, `--markdown-font-size`,
`--markdown-line-height`, `--vscode-editor-font-family`) are only **fallback defaults** (stock VS
Code). At render time `bin/spacedown` reads the user's real preview fonts
(`markdown.preview.fontFamily` / `fontSize` / `lineHeight` + `editor.fontFamily`) from their
`settings.json` and injects a second `<style>` `:root` override AFTER this block, which wins. So the
output matches the user's actual editor, not a stock install. See `bin/spacedown`
(`build_font_override`). To test against a controlled file, set
`SPACEDOWN_SETTINGS=/path/to/settings.json`.

## Refreshing the upstream part

Upstream source (MIT, microsoft/vscode):
`extensions/markdown-language-features/media/markdown.css`

```bash
curl -fsSL "https://raw.githubusercontent.com/microsoft/vscode/main/extensions/markdown-language-features/media/markdown.css" -o /tmp/vscode-markdown.css
```

Then replace part 4 (everything between the `(4) Upstream ... verbatim` marker and the
`(5) markdown.css scopes border colors` marker) with the new file's contents. Re-run
`bash tests/smoke.sh` afterward and compare a render of `tests/fixture/fixture.md` against the
previous one.

Only parts 1-3 and 5 are hand-authored; if a future VS Code release renames a variable or a class,
update those parts to match.

## KaTeX (one version for the panel and the CLI)

KaTeX 0.19.0 (MIT) is pinned in three places that must move together: `integrations/safari/quick-look/Resources/katex.min.js`,
`.../katex.min.css` and the 20 `assets/katex/fonts/*.woff2` files (with the upstream `assets/katex/LICENSE`). To bump it, copy
the new `katex.min.js` and `katex.min.css` from the upstream `dist/` into that Resources dir and the new `fonts/*.woff2` into
`assets/katex/fonts`. `scripts/build-ql-katex` swaps each font's url chain in the stylesheet for the woff2 as a data URI, and
`integrations/build-safari.sh` ships that file inside the Quick Look extension; the bundled CLI reads the same file, so the app
carries the fonts once. In a checkout the CLI inlines the fonts from `assets/katex/fonts` at render time.

## highlight.js (Quick Look only)

`integrations/safari/quick-look/Resources/highlight.min.js` plus `hljs-theme.css` give the Quick Look
panel the syntax colors the pandoc path already had from `--syntax-highlighting tango`. The browser
path does not use them, since pandoc still highlights there.

Upstream is highlight.js 11.11.1 (BSD-3-Clause), fetched 2026-08-25 from cdnjs: the `highlight.min.js`
bundle plus the `github` and `github-dark` theme stylesheets, at
`https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/`.

The vendored bundle matches the cdnjs SRI for that version. Verify a refresh against it before
committing, so a bump cannot quietly ship altered bytes:

```
sha512-EBLzUL8XLl+va/zAsmXwS7Z2B1F9HUHkZwyS/VKwh3S7T/U0nF4BaU29EP/ZSf6zgiIxYAnKLu6bJ8dqpmX5uw==
```

`hljs-theme.css` is the light theme verbatim, then the dark theme wrapped in
`@media (prefers-color-scheme: dark)`, then two rules that drop the themes' own `.hljs` background so
the code block keeps md-style's chrome. Rebuild the file that way after any upstream bump, then run
`node integrations/safari/quick-look/test-render.js`.

## Skim word lists (`EN_WORDS`, `CJK_CHARS` in `skim-surprise.html`)

Both lists are built from public-domain sources, never copied from a third-party list. The sources are in
`scripts/skim-lists/sources.tsv`, each with the evidence for its status:

- Project Gutenberg plain-text editions of works whose contributors all died in 1955 or earlier and that
  were published in 1929 or earlier, each confirmed by a Library of Congress catalog record (LCCN) or the
  dated title page in the file. The file's sha256 is recorded.
- The Markdown documentation of US federal government repositories (public domain in the US under
  17 U.S.C. 105, CC0 worldwide), each pinned to a git revision. These give the English list the technical
  vocabulary Spacedown's pages use.
- Unihan 16.0.0 (Unicode License V3), to fold the Traditional Chinese texts to Simplified.

```bash
node scripts/skim-lists.mjs build                    # fetch, rebuild, compare with the engine (exit 1 if different)
node scripts/skim-lists.mjs build --write            # put the rebuilt lists into assets/skim-surprise.html
node scripts/skim-lists.mjs build --record-hashes    # accept changed source files, then review the list diff
node scripts/skim-lists.mjs check-notices            # offline: every source is credited and has its evidence
```

The build needs network access, `git` and `unzip`; downloads are cached (default: a `spacedown-skim-lists`
folder in the temp dir, `--cache <dir>` to choose). English keys come from the engine's own tokenizer;
Markdown loses its front matter, code, HTML, template tags, link targets and URLs first, and repository
boilerplate (license, contributing, security, changelog files) is skipped. Each literary work counts
equally, and the technical repositories count as one work per agency, so one agency's house words cannot
qualify alone. The English score blends the two corpora 0.7 literary to 0.3 technical, the smallest
technical weight that brings technical-doc coverage back to the level of the lists Skim shipped before
(see `docs/verification/skim-tech-vocab.md`). An entry must appear in at least 40% of the literary works,
50% of the agencies, or 50% of the Chinese works. Ties break by code point, so a rebuild is byte-identical.

A source added to the manifest must be credited in `THIRD_PARTY_NOTICES.md` (by `#<ebook number>`, the
`owner/repo` name, or `Unihan <version>`) and carry evidence, or `node scripts/skim-parity.mjs` and the
smoke parity check fail. After changing the lists, regenerate the Skim goldens against upstream skimgram
with the same lists: `node scripts/skim-parity.mjs --upstream <skimgram clone at 4ebb78a> --write-golden`.
