# Proof of Done, ia-theme-docx

spacedown gains two built-in reading themes, `ia` (the new default) and `tm`, the iA Writer Quattro and Mono variable fonts vendored under the SIL OFL, a Quick Look skin that embeds those fonts at build time, and `bin/spacedown-docx` for iA-styled .docx export. This replaces the private md-preview overlay.

**Date:** 2026-10-16 · **Lane:** normal · **Branch:** `feat/ia-theme-docx` · **Code at:** `de7d128` (proof commit follows)

## Green run

```
Command: bash tests/smoke.sh
Exit: 0
Output:
[41] vendored iA fonts + license
  ok: four font files and the OFL text are vendored
[42] build-ql-skin embeds the four iA fonts
  ok: exactly 4 font data URIs in the built skin; the committed source stays readable
[43] spacedown-docx writes a .docx next to the input in the iA look
  ok: iA docx styles (IBM Plex Sans, ink 1A1A1A)
[44] spacedown-docx drops HTML comments and honors -o
  ok: -o honored, comment dropped
[45] spacedown-docx refuses a missing input with 66
  ok: exit 66
[46] a symlinked spacedown-docx still finds the reference doc
  ok: symlink

smoke: all 59 passed
Verdict: PASS
```

## Negative controls

Each mutation goes through `negctl.sh` (green, mutate, red, restore, green). The tree was clean and committed first.

```
Command: negctl.sh <worktree> "bash tests/smoke.sh" "sed -i '' 's/SPACEDOWN_FONT_MODE:-ia/SPACEDOWN_FONT_MODE:-paper/' bin/spacedown"
Exit: 0
Output:
    FAIL: ia default not behaving                          ([17e])
    FAIL: a theme lost iA Writer Quattro as its first face ([17e4])
  smoke: 57 passed, 2 FAILED
Restore: git checkout HEAD -- bin/spacedown
Verdict: PASS
```

```
Command: negctl.sh <worktree> "bash tests/smoke.sh" "sed -i '' '/Mono V\" italic/d' scripts/build-ql-skin"
Exit: 0
Output:
    FAIL: skin build did not embed exactly 4 fonts         ([42])
  smoke: 58 passed, 1 FAILED
Restore: git checkout HEAD -- scripts/build-ql-skin
Verdict: PASS
```

```
Command: negctl.sh <worktree> "bash tests/smoke.sh" "sed -i '' 's#assets/docx/ia-reference.docx#assets/docx/missing.docx#' bin/spacedown-docx"
Exit: 0
Output:
    FAIL: docx is missing the iA styles                    ([43])
    FAIL: -o ignored or the HTML comment leaked            ([44])
    FAIL: symlink lost the reference doc                   ([46])
  smoke: 56 passed, 3 FAILED
Restore: git checkout HEAD -- bin/spacedown-docx
Verdict: PASS
```

## Notes

- `SPACEDOWN_THEME_CSS` now replaces the CSS of whichever of ia, tm or paper is active (before: paper only). Smoke 17g still passes against the new default.
- The browser `ia` theme names the fonts by family only. spacedown has no mechanism that inlines assets into the standalone page, so an installed font wins and system fonts are the fallback. The Quick Look skin embeds the vendored files.
- A typo in `SPACEDOWN_FONT_MODE` now exits 64 like a bad `--font-mode`; before it rendered with no theme.
- Not run: the macOS app build (xcodebuild, signing). Only `scripts/build-ql-skin` and the smoke suite ran.
