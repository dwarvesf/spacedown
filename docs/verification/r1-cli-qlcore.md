# Proof of Done, r1-cli-qlcore

The `spacedown` CLI renders HTML through the Quick Look JavaScript core (`osascript -l JavaScript`, `assets/sd-cli-render.js`) instead of pandoc and python. pandoc is needed only by `spacedown docx`; without it that subcommand falls back to `textutil`. The page is built in the host order of `docs/contract-r1.md` and calls `SD.boot`. A bundled CLI reads the core from the app's own Quick Look extension.

## Green run

| Command | Exit | Result |
|---|---|---|
| `bash tests/smoke.sh` on main (e07e742d), before | 0 | `smoke: all 155 passed`, 6m10s |
| `bash tests/smoke.sh` on this branch, after | 0 | `smoke: all 164 passed`, 56s |
| `NO_INSTALL=1 bash integrations/build-safari.sh` | 0 | built, signed; bundled CLI 529,587 bytes in 36 files |
| built app copied away, `cli/bin/spacedown` through a symlink: `--version`, math page | 0 | renders from the app's `SpacedownQL.appex/Contents/Resources`, KaTeX fonts inlined |

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
  FAIL: core render: rc=0 shim-called=[pandoc called: --version] err=...
  FAIL: folder render: rc=0
smoke: 42 passed, 2 FAILED
```

The edit was reverted (`git diff` empty) and the same sections ran green again: `smoke: all 44 passed`.

## Not proven

- Math fonts: KaTeX 0.16.11 (the Quick Look core) runs with the 0.16.11 stylesheet and the woff2 files vendored under `assets/katex/fonts` (from 0.19.0). The offline headless check proves the formulas are typeset and the numbers drawn, not pixel parity of the glyphs.
- The Finder Quick Look panel and the Safari drop extension were not exercised; the CLI is the only surface changed.
- Dark-mode screenshots of the new page were not compared with the pandoc page.
