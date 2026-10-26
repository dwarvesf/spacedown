# Verification -- SVG keeps its declared width

A lone SVG used to be forced to the full column width, so a figure designed at 616px rendered at 900px and its labels grew to more than twice the body text. `embed-images.py` now copies a local SVG's `width` attribute onto the img, and the fill rule applies only to SVGs without a width.

| Check | Result |
|---|---|
| Real page (ops-toolkit system-design Day-12), figures measured in a headless browser | shown 616px = natural 616px (was 900px) |
| SVG with only a viewBox | still fills the column (900px) |
| tests/smoke.sh | all 132 passed, including the new svg-width case |
| Negative control: the old embed-images.py | smoke fails the svg-width case, green after restore |

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: declared SVG width carried onto the img, bare SVG left to fill the column
  smoke: all 132 passed
Verdict: PASS
```

## Negative control
```
Command: negctl.sh <repo> "bash tests/smoke.sh" "git show origin/main:assets/embed-images.py > assets/embed-images.py"
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 131 passed, 1 FAILED
Verdict: PASS (restored, green after restore)
```

## Rollback
- Revert the merge commit; pages return to stretching every lone SVG.
