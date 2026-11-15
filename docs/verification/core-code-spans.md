# Proof of Done, core-code-spans

Contract fix to the frozen `ql-render.js`. The core read a `$` or a `> [!x]` inside an inline code span or a fenced block as math or a callout, so a shell snippet broke in the Finder panel. `shieldCode` now swaps every fenced line (also inside a blockquote or list), every inline code span and every escaped `\$` for a placeholder before the callout and math passes, and puts the text back before `marked` parses.

## Green run

```
Command: node integrations/safari/quick-look/test-render.js
Exit: 0
Output (new checks):
  ok: code span keeps $HOME and $(cmd) literal
  ok: fence keeps $VAR and $(cmd) literal
  ok: fenced > [!note] stays code
  ok: fence inside a blockquote keeps $ literal
  ok: escaped \$ stays a dollar
  ok: real callout beside code still a callout
  ok: real inline and display math beside code still render
ql-render: PASS
Verdict: PASS
```

```
Command: bash tests/smoke.sh --only quicklook,render,katex,xray,present
Exit: 0
Output: smoke: all 35 passed
Verdict: PASS
```

`test-contract.js`, `test-boxdraw.js`, `test-xray.js`, `test-present.js`: all PASS.

## Negative control

The new tests were written first and ran against the old core (`git show HEAD:.../ql-render.js`), with the new `test-render.js`:

```
Command: node integrations/safari/quick-look/test-render.js
Exit: 1
Output:
  FAIL: code span keeps $HOME and $(cmd) literal
  FAIL: fence keeps $VAR and $(cmd) literal
  FAIL: fenced > [!note] stays code
  FAIL: escaped \$ stays a dollar
  FAIL: real inline and display math beside code still render
ql-render: 5 FAILED
Verdict: RED as expected
```

With the fix restored: `ql-render: PASS`.

## Effect on the CLI driver (PR #71)

`assets/sd-cli-render.js` in #71 carries `protectCode`, `guard`, `unguard` and an `hljs.highlight` wrapper that work around this bug from outside the core. With this fix they are redundant: the core shields the same three cases (code spans, fences, `\$`). They do no harm, so #71 can drop them in a follow-up.

## Not verified

- A live Finder spacebar preview (needs the GUI and an installed build).
- Indented (four-space) code blocks are not shielded; only fences and spans are. A code span that crosses a line break is not shielded either.
