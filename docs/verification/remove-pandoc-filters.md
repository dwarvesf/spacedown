# Proof of Done, remove-pandoc-filters

Release 1 moved rendering to the Quick Look JavaScript core. Nine pandoc-era files in `assets/` were left unread. They are deleted: `assets/katex/katex.min.js`, `assets/katex/katex.min.css`, and `embed-images.py`, `inline-katex.py`, `eq-labels.py`, `tsv-tables.py`, `frontmatter-to-table.py`, `callouts-to-html.py`, `details-summary.py`. `tables-blankline.py` (docx) and `assets/katex/fonts` stay.

## Unused check

`git grep -n <basename>` outside `docs/verification` found only comments (`assets/sd-cli-render.js`, `ql-render.js`, theme CSS), `--exclude` flags in `scripts/bundle-cli`, an absence assertion in `tests/smoke.sh`, and one note in `assets/REFRESH.md` (removed here). No script, test or build step reads any of the nine. The only real reader of `katex.min.js` and `katex.min.css` was the deleted `inline-katex.py`; the CLI reads the Quick Look copies.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh --only cli,docx,katex,bundle,shot` | 0 | PASS, 69 passed |
| `bash tests/smoke.sh` | 0 | PASS, 164 passed |
| `NO_INSTALL=1 bash integrations/build-safari.sh` | 0 | PASS, app built and signed |

```
Command: bash tests/smoke.sh --only cli,docx,katex,bundle,shot
Exit: 0
Output:
  ok: 6 of 6 formulas typeset with the network blocked, 2 equation numbers drawn, no KaTeX error
  ok: SD.plugins() = boxdraw,xray,present, SD.errors empty, no marked in the page
smoke: all 69 passed
Verdict: PASS

Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: present suite passes
smoke: all 164 passed
Verdict: PASS

Command: NO_INSTALL=1 bash integrations/build-safari.sh
Exit: 0
Output:
  .../Release/Spacedown.app: replacing existing signature
  .../Release/Spacedown.app
  build-exit=0
Verdict: PASS
```

## Negative control

`assets/katex/fonts` moved away, then `bash tests/smoke.sh --only katex`:

```
  FAIL: katex: the Quick Look KaTeX script or stylesheet is missing, or 20 font(s) are not vendored in assets/katex/fonts
```

The fonts were restored afterwards; the suite is green with them in place.

## Rollback

Revert this commit to restore the nine files.
