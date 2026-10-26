# Verification -- --shot warns when KaTeX draws red

KaTeX marks a parse error with `.katex-error` but draws an unknown macro (`\C`, `\dyad`, `\tensor`) in red MathML with no error class, so counting `.katex-error` missed six learning lessons in ops-toolkit. The `--shot` probe now counts both and prints `WARN katex: N formula part(s) render in red ...` naming up to five.

| Check | Result |
|---|---|
| A page with `$\C$` and `$\dyad{0}$` | `WARN katex: 2 formula part(s) ... \C | \dyad` |
| A page with clean math | no WARN katex line |
| tests/smoke.sh | all 139 passed, including both new cases |
| Negative control: the previous bin/spacedown | smoke fails the katex case, green after restore |

## Green run
```
Command: bash tests/smoke.sh
Exit: 0
Output:
  ok: an unknown KaTeX macro prints a WARN katex line naming it
  ok: clean math prints no WARN katex line
  smoke: all 139 passed
Verdict: PASS
```

## Negative control
```
Command: negctl.sh <repo> "bash tests/smoke.sh" "git show origin/main:bin/spacedown > bin/spacedown"
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 138 passed, 1 FAILED
Verdict: PASS (restored, green after restore)
```

## Rollback
- Revert the merge commit; --shot goes back to the wide-table warning only.
