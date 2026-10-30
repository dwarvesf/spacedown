# Verification -- feat-wide-table-names-row

`spacedown --shot` now names the body cell whose min-content width drives the overflow (row, column, first 40 characters, flagged when the run is inline code) in each `WARN wide table` line. The existing prefix is unchanged.

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: a very wide table prints a WARN wide table line
  ok: the wide-table WARN names the cell with the widest unbreakable run (row 10 col 2, inline code)
smoke: all 140 passed
Verdict: PASS
```
```
Command: bin/spacedown fixture.md --out fixture.html --shot fixture.png   (3-column Vietnamese table, 10 body rows)
Exit: 0
Output:
spacedown: WARN wide table #1: 992 px wide in a 1206 px container (scrolls sideways at 1300px); widest unbreakable cell row 10 col 2: "OLLAMA_NUM_PARALLEL 1, kiểu KV chưa đặt" (inline code)
Verdict: PASS
```

## Negative control
```
Command: git checkout origin/main -- bin/spacedown && bash tests/smoke.sh   (probe change reverted, then restored with git checkout HEAD -- bin/spacedown)
Exit: 1
Output:
  FAIL: --shot wide cell: rc=0 out=spacedown: rendering .../shot-cell.md (926 bytes) via pandoc... (no "widest cell" detail)
smoke: 139 passed, 1 FAILED
Verdict: FAIL as expected without the probe change; PASS again after restore (smoke: all 140 passed)
```

## Not proven
- The culprit is the cell with the widest min-content, measured on an off-screen one-cell table with the layout floor (`min-width: 22ch`) zeroed. Ties on a plain wrapped cell fall to the first such cell.
- The `(inline code)` flag is a width test (the code span fills the cell's min-content), not a parse of the markdown.
