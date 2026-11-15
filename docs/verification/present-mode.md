# Proof of Done, present-mode

Present mode, in two layers, because the Finder panel runs no JavaScript. Render time (`transform`, `controls`, `toolbar`, `css`) cuts the document into `<section class="sd-slide">` wrappers at each top-level H2 and each thematic break; the H1 and anything before the first cut is the title slide. A hidden checkbox `#sd-present`, a "Present" toolbar label and CSS scroll snapping (`scroll-snap-type: y mandatory`, slides at least `100vh`) turn it into slides with no script. Page time (`init`, `key`, `print`, `reset`, under `SD.boot`) adds P, arrows, Page Up/Down, Home/End, Esc and a "3 / 7" counter. Unchecked, the page reads as before.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `node integrations/safari/quick-look/test-present.js` | 0 | PASS |
| `bash tests/smoke.sh --only present,quicklook` | 0 | PASS |

```
Command: node integrations/safari/quick-look/test-present.js && bash tests/smoke.sh --only present,quicklook
Exit: 0
Output:
  present: PASS
  [present] Present mode plug-in
    ok: present suite passes
  smoke: all 6 passed
Verdict: PASS
```

What the suite pins: the split rules (H2, `---`, no headings is one slide, H2 or `---` inside a blockquote, details or code block does not split, no empty slides), the title slide, math and code inside slides, and that with the wrappers stripped the body is byte for byte the render without the plug-in. Page time runs in node against a fake document.

Not verified here: arrow and Page Down snapping in a live Quick Look panel, and the Finder panel itself (the screenshots come from headless Helium on the page the appex builds).

## Negative control

The code was committed first (3aead40), then `present.js` was mutated so container depth is never counted (an H2 or `---` inside a blockquote or details splits the slide). Restored with `git checkout`, green again.

```
Command: bash tests/smoke.sh --only present,quicklook
Exit: 1 (under mutation, RED expected)
Output:
  FAIL: an H2 or --- inside a blockquote or details does not split
  smoke: 5 passed, 1 FAILED
After restore: smoke: all 6 passed
Verdict: PASS
```

## Rollback

Revert the merge commit: two source files, `present.js` and `test-present.js`.
