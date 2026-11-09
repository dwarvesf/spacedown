# Verification -- math renders offline, labeled equations are numbered

Two fixes for pages with math. KaTeX now ships inside the page (`assets/inline-katex.py` plus the vendored `assets/katex/`), so a browser with no route to the CDN still typesets. A one-line `$$ f $$ {#eq-id}` becomes a numbered equation with an anchor (`assets/eq-labels.py`, run before pandoc).

| Check | Result |
|---|---|
| Fixture `tests/fixture/math-offline.md`, Helium headless, `--host-resolver-rules="MAP * ~NOTFOUND"`, this branch | 6 of 6 formulas typeset, numbers (1) and (2) at the right |
| Same fixture rendered by main (CDN), same browser flags | raw TeX, `{#eq-energy}` shown as text |
| Page size, same fixture | 963,060 bytes on main, 1,604,711 here: +641,651 bytes, only on pages with math |
| tests/smoke.sh | all 146 passed |
| Negative control: both new passes replaced by no-ops | 4 of the new cases FAIL, green after restore |

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: bin/spacedown pins katex@0.19.0 and assets/katex is that version
  ok: 6 of 6 formulas typeset with the network blocked, 2 equation numbers drawn
  smoke: all 146 passed
Verdict: PASS
```

## Negative control
```
Command: bash tests/smoke.sh with assets/inline-katex.py and assets/eq-labels.py emptied
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 142 passed, 4 FAILED
Verdict: PASS (restored, green after restore)
```

## Rollback
- Revert the commit; each pass is one script and one stage in the render chain, and `assets/katex/` is only read by the inliner.
