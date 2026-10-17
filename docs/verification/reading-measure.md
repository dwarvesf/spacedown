# Proof of Done, reading-measure

On a large screen the 60rem reading column let the eye travel too far side to side. The column is now one custom property, `--sd-measure: 50rem`, read by the body, prose, tables, section rules and the RSVP stage. Phone behaviour is unchanged (the viewport caps the column below 50rem). The Quick Look skin and the docx export keep their own widths.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
[13] page column overrides pandoc default
  ok: var(--sd-measure) column wins over pandoc 36em; prose fills it
[13a] reading measure is one 50rem property
  ok: --sd-measure: 50rem, used by body, prose, tables, rules and the RSVP stage
smoke: all 117 passed
```

## Negative control

`--sd-measure` set back to 60rem in `assets/vscode-preview-head.html`, same suite, then restored with `git checkout --`:

| State | Result |
|---|---|
| 60rem (control) | `FAIL: reading measure is not a single 50rem --sd-measure property`, `smoke: 116 passed, 1 FAILED` |
| 50rem (restored) | `smoke: all 117 passed` |

## Layout check

`scripts/layout-check --widths 390,768,1470,1728` on a long English research doc, headless Helium, ia mode. Content box is the left-right edge of the text; no width scrolls sideways.

| window | viewport | overflow | content box | gap left / right |
|---|---|---|---|---|
| 390px | 392 | no | 20-372 | 20 / 20 |
| 768px | 760 | no | 52-708 | 52 / 52 |
| 1470px | 1462 | no | 408-1308 | 168 / 154 |
| 1728px | 1720 | no | 537-1437 | 297 / 283 |

At 1470 and 1728 the content box is 900px (50rem at the 18px root); at 60rem it was 1080px.

## Characters per line

Longest prose paragraph (743 characters) at a 1470px window, same page rendered at 60rem and 50rem. Lines counted from the paragraph's client rects; capacity is column width divided by the width of "0" in the body font (10.80px).

| measure | column width | lines | average chars per line | capacity (width / "0") |
|---|---|---|---|---|
| 60rem (before) | 1080px | 7 | 106.1 | 100.0 |
| 50rem (after) | 900px | 9 | 82.6 | 83.3 |

The body font in ia mode is proportional (iA Writer Quattro), so the old "~94 mono chars" figure and the new "~78" are the same estimate basis; the measured drop is about 100 to 83 characters of capacity, 17 percent fewer.

## Not aligned

| Surface | Width rule | Decision |
|---|---|---|
| Quick Look / Safari skin | `--ql-measure: 38rem` in `integrations/safari/quick-look/Resources/ql-reading.css`, its own template measure | left alone |
| docx export | US Letter, 1.5 in side margins (about 70 characters), `scripts/build-docx-reference.py` | left alone |

## Rollback

Revert the commit, or set `--sd-measure` back to 60rem in `assets/vscode-preview-head.html`.
