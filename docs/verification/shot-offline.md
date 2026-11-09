# Proof of done: `--shot --offline`

`spacedown <file> --shot <png> --offline` runs the screenshot browser with `--host-resolver-rules=MAP * ~NOTFOUND`, so the PNG shows what a reader with no network sees. `--offline` without `--shot` refuses with exit 64.

| Check | Result |
|---|---|
| Full smoke suite on `feat/shot-offline` | PASS, 149 of 149 |
| Negative control: resolver flag removed from `bin/spacedown` | FAIL as expected, 148 passed, 1 failed |

## Green run

Command: `bash tests/smoke.sh`
Exit: 0
Output:
```
  ok: --offline without --shot exits 64 with a clear message and renders nothing
[--shot --offline] the screenshot browser resolves no hostnames
  ok: --shot --offline writes a PNG that differs from the online one (the remote image is gone)
  ok: --shot --offline on the math fixture: PNG written, no katex warning (KaTeX is inlined)
smoke: all 149 passed
```
Verdict: PASS

## Negative control

Command: remove the resolver line from `run_shot_browser` in `bin/spacedown`, run `bash tests/smoke.sh`, then `git checkout -- bin/spacedown`
Exit: 1
Output:
```
  FAIL: --shot --offline: online rc=0 offline rc=0, PNGs identical or missing
smoke: 148 passed, 1 FAILED
```
Verdict: PASS (the new test goes red without the flag)
