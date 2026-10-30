# Verification -- feat-wide-table-names-row

`spacedown --shot` now names the widest body cell (row, column, first 40 characters) in each `WARN wide table` line. The existing prefix is unchanged.

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: a very wide table prints a WARN wide table line
  ok: the wide-table WARN names the widest cell by row, column and text
smoke: all 140 passed
Verdict: PASS
```
```
Command: bin/spacedown fixture.md --out fixture.html --shot fixture.png   (3-column Vietnamese table, 10 body rows)
Exit: 0
Output:
spacedown: WARN wide table #1: 992 px wide in a 1206 px container (scrolls sideways at 1300px); widest cell row 7 col 2: "14,905 ms lạnh, 3,392 ms ấm, dùng lại 8,"
Verdict: PASS
```

## Negative control
```
Command: git checkout origin/main -- bin/spacedown && bash tests/smoke.sh   (probe change reverted, then restored with git checkout HEAD -- bin/spacedown)
Exit: 1
Output:
NEGATIVE_OUTPUT
Verdict: FAIL as expected without the probe change; PASS again after restore (smoke: all 140 passed)
```

## Not proven
- The culprit is the cell with the widest one-line text relative to its cell width. It is a heuristic: it names the cell that most likely forces the width, not the exact column the browser clips.
- Cells holding images or wide inline code are measured by their text only.
