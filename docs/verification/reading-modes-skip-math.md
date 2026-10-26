# Verification -- reading-modes-skip-math

A saved reading mode (BeeLine, Skim, Bionic) no longer wraps the raw TeX inside `.math` spans before KaTeX typesets them. Before the fix, pandoc's KaTeX loop met a span with no text child, threw, and left every later formula raw. Seen in Orca with `sd-read-mode: beeline` saved: 1 of 882 formulas typeset on a learning lesson.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
Command: bash tests/smoke.sh
Exit: 0
Output:
[read-math] a saved reading mode never touches math: every formula still typesets
  ok: beeline saved: all formulas typeset
  ok: skim saved: all formulas typeset
  ok: bionic saved: all formulas typeset
smoke: all 131 passed
Verdict: PASS
```

## Negative control

```
Command: negctl.sh: bash tests/smoke.sh under `git show origin/main:assets/reading-chrome-foot.html > assets/reading-chrome-foot.html`
Exit: 1 (under mutation)
Output:
  FAIL: beeline saved: some formulas stayed raw TeX
  FAIL: skim saved: some formulas stayed raw TeX
  FAIL: bionic saved: some formulas stayed raw TeX
smoke: 128 passed, 3 FAILED
Verdict: RED as expected; green again after `git checkout HEAD --`
```

## Not proven

- RSVP was not seeded in the test; it reads through `READ_SKIP`, which carries the same `.math` entry.
