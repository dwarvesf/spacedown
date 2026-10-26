# Verification -- self-check spacing and tsv/csv tables

Two render faults on a learning Day (ops-toolkit system-design Day-12): consecutive `<details>` sat flush, so an open answer ran into the next question, and the ```tsv Anki block was a code block whose rows ran off the page. iA Writer's own Quattro template renders both the same way (checked by rendering the sections with its `style.css`), so spacedown now does better than the reference: every theme spaces the questions and indents an open answer under a hairline, and `assets/tsv-tables.py` turns a ```tsv or ```csv fence into a wrapping table (pandoc runs with `--preserve-tabs` so the columns survive).

| Check | Result |
|---|---|
| Day-12 sections 9 and 10, light and dark screenshots | questions evenly spaced, answers indented; Anki block is a two-column table |
| tests/smoke.sh | all 137 passed, including the new tsv and details-css cases |
| Negative control: the tsv filter replaced by a pass-through | smoke fails the tsv case, green after restore |

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: tsv and csv fences became tables
  ok: ia-theme has the details rules
  smoke: all 137 passed
Verdict: PASS
```

## Negative control
```
Command: negctl.sh <repo> "bash tests/smoke.sh" "replace assets/tsv-tables.py with a pass-through"
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 136 passed, 1 FAILED
Verdict: PASS (restored, green after restore)
```

## Rollback
- Revert the merge commit; details return to flush stacking and tsv fences to code blocks.
