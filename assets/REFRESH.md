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
