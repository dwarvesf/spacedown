# Proof of done: smoke font checks accept woff2

The [fonts] and skin checks in tests/smoke.sh counted only `data:font/ttf` URIs, so the woff2 switch in #63 could not pass. They now accept ttf or woff2 with the same counts.

```
Command: bash tests/smoke.sh --only fonts,render
Exit: 0
Output:
  ok: exactly 4 font data URIs in the built skin; the committed source stays readable

smoke: all 23 passed
Verdict: PASS
```
