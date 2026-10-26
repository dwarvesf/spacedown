# Verification -- numbered details summary stays on one line

pandoc parsed `<details><summary>1. Question</summary>` as an ordered list that swallowed the summary, so a learning self-check showed a bare disclosure triangle with the question below it. `assets/details-summary.py` escapes a list or heading marker that opens a summary, wired into the HTML render chain.

| Check | Result |
|---|---|
| ops-toolkit system-design Day-12 self-check | `<summary> 1. Why can a fixed window ... </summary>`, one line |
| tests/smoke.sh | all 133 passed, including the new details case |
| Negative control: the pre-pass replaced by a pass-through | smoke fails the details case, green after restore |

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: summary kept inline with its number
  smoke: all 133 passed
Verdict: PASS
```

## Negative control
```
Command: negctl.sh <repo> "bash tests/smoke.sh" "replace assets/details-summary.py with a pass-through"
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 132 passed, 1 FAILED
Verdict: PASS (restored, green after restore)
```

## Rollback
- Revert the merge commit; the pass is one script and one pipe stage.
