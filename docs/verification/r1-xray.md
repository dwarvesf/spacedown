# Verification -- Writing X-ray lens (release 1, Q3)

`xray.js` marks dashes, long sentences, filler words and ticket IDs at render time, so it works in the Finder panel with no JavaScript. A hidden checkbox `#sd-xray` plus `#sd-xray:checked ~ * .sd-xr-RULE` CSS turns the marks on; the toolbar label carries a legend. No `:has()`, no regex lookbehind (macOS 12 JavaScriptCore).

| Check | Result |
|---|---|
| Each rule on and off (dashes, long sentences, fillers, ticket IDs) | marked when on, no marks when off |
| `xraySentenceWords` | 25 words pass, 26 marked; 40 lets 26 pass; 8 marks 12 |
| Vietnamese (NFC and NFD) | word count equals the space-separated count; fillers whole-word |
| Code, pre, math, link URLs | no marks inside, bytes preserved |
| Contrast and lightness | every fill 4.5:1 or better against its ink, light and dark; four fills at least 6 L* apart |
| 2,000 words | about 1 ms median in node (limit 50) |

## Green run
```
Command: node integrations/safari/quick-look/test-xray.js && bash tests/smoke.sh --only xray,quicklook
Exit: 0
Output:
  ok: dashes: em, en and the &mdash; entity are marked
  ok: light: every fill has contrast 4.5 or more with its ink (lowest 7.0)
  ok: speed: 2017 words marked in 0.9 ms median (limit 50)
  xray: PASS
  [xray] Writing X-ray plug-in
    ok: xray suite passes
  smoke: all 6 passed
Verdict: PASS
```

## Negative control
```
Command: set DASH_RE in Resources/xray.js to a pattern that never matches, then node integrations/safari/quick-look/test-xray.js
Exit: 1 (under mutation, RED expected)
Output:
  FAIL: dashes: em, en and the &mdash; entity are marked
  FAIL: prose is marked (dash, filler, ticket)
  xray: 5 FAILED
  FAIL: xray suite failed (run integrations/safari/quick-look/test-xray.js for the detail)
Verdict: PASS (restored with git checkout, green after restore)
```

## Rollback
Revert the PR: `xray.js` goes back to the registering stub.
