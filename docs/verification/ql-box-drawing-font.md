# Proof of Done, ql-box-drawing-font

Box-drawing diagrams in the real Finder Quick Look panel had right edges about 6 px left of the corners and gaps in vertical bars. Root cause confirmed: iA Writer Mono has no box-drawing glyphs, so they fell back per glyph to a font with another advance. The browser theme already carried the fix (`@font-face "SD Diagram Fallback"`, Menlo at `size-adjust: 99.6594%`); the Quick Look skin did not. This is a contract PR: `Resources/ql-reading.css` is frozen by `docs/contract-r1.md`.

## Before and after (live Finder panel, same diagram fixture)

| | Capture | What it shows |
|---|---|---|
| Before (1.1.0) | `docs/verification/ql-box-drawing-font/before.png` | Right edges and corners offset, vertical bars broken |
| After (this branch, Developer ID signed, installed to /Applications, `qlmanage -r` + `-r cache`, `qlmanage -p`, 12 s wait, `screencapture -l`) | `docs/verification/ql-box-drawing-font/after.png` | Corners, edges and verticals join; arrows and tree view intact |

The boxdraw `line-height: 1.2` still applies in the panel and the verticals join with Menlo at that value, so it is unchanged.

## Green run

```
Command: bash tests/smoke.sh --only quicklook,fonts,render
Exit: 0
Output: smoke: all 28 passed
Verdict: PASS
```

```
Command: bash tests/smoke.sh
Exit: 0
Output: smoke: all 192 passed
Verdict: PASS
```

## Negative control

| Step | Command | Result |
|---|---|---|
| Face present | `node integrations/safari/quick-look/test-boxdraw.js` | `boxdraw: PASS` |
| `@font-face` block deleted from `ql-reading.css` | same command | `FAIL: built skin carries the SD Diagram Fallback face, Menlo, box-drawing range, after iA Mono`, `boxdraw: 1 FAILED` |
| Source restored | same command | `boxdraw: PASS` |

The test also checks two mutated copies of the built skin in memory (face removed; face listed before iA Mono): both must fail the check.

## Reproduce

`bash tests/smoke.sh --only quicklook`, then for the live check `SIGN_ID=<Developer ID> APP_DEST=/Applications integrations/build-safari.sh`, `qlmanage -r; qlmanage -r cache; qlmanage -p <md with a box-drawing fence>`.
