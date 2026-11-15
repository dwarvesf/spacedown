# Proof of Done, r1-boxdraw-fonts

Two changes for the Quick Look panel. Box diagrams: `boxdraw.js` marks code blocks that hold box-drawing characters (U+2500 to U+257F) or arrow glyphs with `sd-boxdraw`, and its `css` hook sets those blocks to `line-height: 1.2` so vertical lines join. A plain code block keeps 1.5. Fonts: the four iA Writer fonts are embedded as full woff2 (no subsetting) instead of base64 TTF. The woff2 files sit next to the TTFs in `assets/fonts/ia/`, so the build needs no Python tool.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `node integrations/safari/quick-look/test-boxdraw.js` | 0 | PASS, 10 checks |
| `bash tests/smoke.sh --only quicklook,fonts,render`, on main with #64 merged in | 0 | PASS, 28 checks |
| `NO_INSTALL=1 bash integrations/build-safari.sh` | 0 | PASS |

```
Command: node test-boxdraw.js
Exit: 0
Output:
  ok: boxdraw registers with SD, first
  ok: box-drawing fence gets sd-boxdraw
  ok: css gives sd-boxdraw line-height 1.2
  ok: arrow glyph in a highlighted fence is marked
  ok: triangle arrow is marked
  ok: plain code block is not marked
  ok: plain highlighted block is not marked
  ok: inline code and prose are not marked
  ok: only the tree block of three is marked
  ok: indented code block is marked
  ok: no hook errors

boxdraw: PASS
Verdict: PASS
```

```
Command: bash tests/smoke.sh --only quicklook,fonts,render
Exit: 0
Output:
[41] vendored iA fonts + license
  ok: four font files and the OFL text are vendored
[42] build-ql-skin embeds the four iA fonts
  ok: exactly 4 font data URIs in the built skin; the committed source stays readable

smoke: all 28 passed
Verdict: PASS
```

The font checks in `tests/smoke.sh` accept ttf or woff2 since PR #64, merged into this branch (no smoke.sh edit here). The TTFs stay: smoke check 41 and `bundle-1` need them, and the README tells users to install them. Nothing in `build-ql-skin` or `ia-fontface-css` copies them anywhere; the bundled CLI gets them from the `bundle-cli` rsync of `assets/`.

## Measured

| What | Before | After |
|---|---|---|
| Built QL skin CSS (`build-ql-skin`) | 790355 B | 267867 B |
| `SpacedownQL.appex` (`du -sk`) | 1468 KB | 960 KB |
| `Spacedown.app` (`du -sk`) | 3520 KB | 3208 KB (same after the merge of #64) |
| Font payload, 4 files | 588 KB TTF | 194 KB woff2 |

The app shrinks less than the appex because `assets/` ships in the bundled CLI, which now carries the four woff2 files next to the TTFs.

## Negative control

| Change | Result |
|---|---|
| `boxdraw.js` back to the stub | `boxdraw: 6 FAILED` (fence, css, arrow, triangle, tree, indented) |
| `ia-fontface-css` back to base64 TTF, with the smoke change applied | `[42] FAIL: skin build did not embed exactly 4 fonts` |

```
Command: node test-boxdraw.js, with Resources/boxdraw.js reverted to the stub
Exit: 1
Output:
  FAIL: box-drawing fence gets sd-boxdraw
  FAIL: css gives sd-boxdraw line-height 1.2
  FAIL: arrow glyph in a highlighted fence is marked
  FAIL: triangle arrow is marked
  FAIL: only the tree block of three is marked
  FAIL: indented code block is marked

boxdraw: 6 FAILED
Result: RED as expected
```

## Not verified

No live Finder panel render. The line-height value is the one the test render showed joining lines at 1.2.

The upright Quattro V carries Greek, Cyrillic and Vietnamese. The other three files lack Greek (746 glyphs), so Greek in italics or in code falls back to a system font. The woff2 files hold every glyph of their TTFs.

## Rollback

Revert the commit. The TTFs are untouched.

## Final run

```
Command: node integrations/safari/quick-look/test-boxdraw.js
Exit: 0
Output:
boxdraw: PASS
Verdict: PASS
```
