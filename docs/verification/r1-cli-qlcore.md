# Proof of Done, r1-cli-qlcore

The `spacedown` CLI renders HTML through the Quick Look JavaScript core (`osascript -l JavaScript`, `assets/sd-cli-render.js`) instead of pandoc and python. pandoc is needed only by `spacedown docx`; without it that subcommand falls back to `textutil`. The page is built in the host order of `docs/contract-r1.md` and calls `SD.boot`. A bundled CLI reads the core from the app's own Quick Look extension.

## Green run

```
Command: bash tests/smoke.sh   (main e07e742d, before)
Exit: 0
Output:
smoke: all 155 passed
real	6m9.7s
Verdict: PASS (baseline)
```

```
Command: bash tests/smoke.sh   (this branch, after)
Exit: 0
Output:
[core-1] an HTML render runs neither pandoc nor python, and still typesets math offline
  ok: rc 0, no pandoc or python call, math with inlined fonts, outline and code blocks present
[core-2] a folder render also runs without pandoc
  ok: index written, both files rendered
[core-3] the app's stored settings reach the page, except the theme: --font-mode alone sets that
  ok: textSize 22 applied; the stored theme tm is ignored (ia default); --font-mode paper sets the theme
[core-4] the page boots the plug-ins (SD.boot) and carries no core engine
  ok: SD.boot called with the settings; plug-ins inline; marked and KaTeX scripts not in the page
[core-5] --no-standalone writes the body fragment only
  ok: headings with ids, no html, head or script
[core-6] --version reports pandoc as optional
  ok: pandoc optional
[core-7] spacedown docx without pandoc falls back to textutil, with one note on stderr
  ok: a .docx from textutil, stdout is the path, one stderr note
[core-8] --watch re-renders on save and keeps the live-reload script
  ok: the saved edit shows in the page; the poll script survived the re-render
[core-4b] in a browser the page boots the plug-ins without errors
  ok: SD.plugins() = boxdraw,xray,present, SD.errors empty, no marked in the page

smoke: all 164 passed
real	0m55.7s
Verdict: PASS
```

```
Command: NO_INSTALL=1 bash integrations/build-safari.sh, then the built app's cli/bin/spacedown (copied away, run through a symlink): --version, a math page
Exit: 0
Output:
build-safari: signing (- + runtime + entitlements)...
spacedown 1.1.0
  renderer: Quick Look core (osascript, no pandoc needed for HTML)
spacedown: wrote .../app-math.html (585948 bytes)   (katex spans and woff2 fonts present, read from SpacedownQL.appex/Contents/Resources)
Verdict: PASS
```

New checks (all in the `cli` and `katex` sections): `[core-1]` an HTML render runs neither pandoc nor python (shims that record a call and fail are first on `PATH`), `[core-2]` folder mode without pandoc, `[core-3]` stored app settings reach the page, `[core-4]` and `[core-4b]` `SD.boot` is called and, in a headless browser, the plug-ins `boxdraw,xray,present` register with `SD.errors` empty, `[core-5]` `--no-standalone` writes the body only, `[core-6]` `--version` says pandoc is optional, `[core-7]` `docx` without pandoc writes a `.docx` through `textutil` with one stderr note, `[core-8]` `--watch` re-renders on save and keeps the live-reload script.

Render time per file, three runs each, best of three, same machine:

| File | pandoc path | Quick Look core |
|---|---|---|
| `README.md` (23 KB) | 0.49 s | 0.18 s |
| `tests/fixture/fixture.md` | 0.38 s | 0.14 s |
| `tests/fixture/math-offline.md` | 0.35 s | 0.14 s |
| `tests/fixture/reading-en.md` | 0.64 s | 0.13 s |

Bundled CLI (`scripts/bundle-cli`): 1,424,082 bytes before, 529,587 after (the real build) (no second KaTeX, no iA TTFs, no python filters).

## Negative control

Run after this file was committed. `run_renderer` in `bin/spacedown` made to call `pandoc --version` first, `bash tests/smoke.sh --only cli,katex`:

```
Command: bash tests/smoke.sh --only cli,katex   (with run_renderer calling pandoc first)
Exit: 1
Output:
  FAIL: core render: rc=0 shim-called=[pandoc called: --version] err=...
  FAIL: folder render: rc=0
smoke: 42 passed, 2 FAILED
Result: RED as expected
```

The edit was reverted (`git diff` empty); the re-run is the last block of this file.

## Not proven

- Math fonts: KaTeX 0.16.11 (the Quick Look core) runs with the 0.16.11 stylesheet and the woff2 files vendored under `assets/katex/fonts` (from 0.19.0). The offline headless check proves the formulas are typeset and the numbers drawn, not pixel parity of the glyphs.
- The Finder Quick Look panel and the Safari drop extension were not exercised; the CLI is the only surface changed.
- Dark-mode screenshots of the new page were not compared with the pandoc page.

## Re-run after the revert

```
Command: bash tests/smoke.sh --only cli,katex
Exit: 0
Output:
smoke: all 44 passed
Verdict: PASS
```
