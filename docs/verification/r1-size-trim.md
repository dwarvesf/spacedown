# Proof of Done, r1-size-trim

The app was 3,421,766 bytes before this change and is 3,274,913 after (sum of file sizes, headless build). The budget is 2 MB for the app and 1 MB for the DMG; this change does not reach it and says so below. It trims what sits in its own files, and adds the check the wave join runs.

| Change | Before | After | Where |
|---|---|---|---|
| highlight.js: custom build of 19 languages (bash, shell, javascript, typescript, json, yaml, ini and toml, python, go, rust, swift, sql, xml and html, css, markdown, diff, dockerfile, makefile, plaintext) from tag 11.11.1 | 127,496 | 79,927 | `integrations/safari/quick-look/Resources/highlight.min.js`, rebuilt by `scripts/hljs-build` |
| APP `Resources/Icon.png`: nothing loads it (the first-launch window draws its tile in CSS, the Dock icon comes from the asset catalog), so it is a 16 px stub | 100,020 | 736 | `integrations/safari/SpacedownDrop/SpacedownDrop/Resources/Icon.png` |
| Safari drop extension out of the default build | already opt-in through `build-safari.sh --with-safari`; `release.sh` now stops if the appex is in the release or store build | | `scripts/release.sh` |
| `scripts/size-budget <app> [dmg]` | new: fails over 2 MB (app, sum of file sizes) or 1 MB (dmg file) and names the largest files | | `scripts/size-budget` |

Not done, and why:

- `Icon.png` stays as a stub, not deleted: `SpacedownDrop.xcodeproj/project.pbxproj` (frozen) lists it in the Resources phase, so a missing file breaks the build. Removing the pbxproj lines needs a contract PR.
- Shrinking the AppIcon PNGs saves 196 KB in the repo and nothing in the app: `Assets.car` stores raw LZFSE bitmaps, so the built size did not move (253,592 bytes before and after). That change was reverted.
- The app is still 1,274,913 bytes over. The files that carry it are not in this node's row: `ql-reading.css` 790,355 (four iA fonts as data URIs), KaTeX twice (275,414 in the appex and 272,868 in `cli/assets/katex`), `cli/assets/fonts/ia` 585,148 (the same fonts a second time), `Assets.car` 253,592.
- DMG (UDZO) measured 1,728,934 before and 1,613,258 after, over the 1 MB budget.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh --only quicklook,render,bundle,notary,katex` | 0 | PASS, 43 checks |
| `node integrations/safari/quick-look/test-render.js` | 0 | PASS (highlighting of `py`, unknown language untouched, no-hljs fallback) |
| `node tests/hljs-bundle-test.js` | 0 | PASS, every listed language and alias gets token spans, bundle under 100,000 bytes |
| `bash tests/size-budget-test.sh` | 0 | PASS, 5 checks |
| `NO_INSTALL=1 bash integrations/build-safari.sh` | 0 | builds, signature verifies |

Command: the five runs above, in order
Exit: 0
Output:

```
$ bash tests/smoke.sh --only quicklook,render,bundle,notary,katex
smoke: all 43 passed
exit: 0
$ node integrations/safari/quick-look/test-render.js
ql-render: PASS
$ node tests/hljs-bundle-test.js
  ok   plaintext renders
  ok   an unlisted language stays unknown
  ok   bundle is under 100000 bytes (79927)
hljs-bundle-test: all passed
$ bash tests/size-budget-test.sh
  ok   1.5 MB app passes
  ok   app and 0.9 MB dmg pass
  ok   2.1 MB app fails and names the biggest file
  ok   1.1 MB dmg fails
  ok   a missing app is a usage error
size-budget-test: 5 passed, 0 failed
$ bash scripts/size-budget <built app>
size-budget: app 3274913 bytes (budget 2000000)
size-budget: FAIL app is 1274913 bytes over budget; largest files:
     790355  Contents/PlugIns/SpacedownQL.appex/Contents/Resources/ql-reading.css
```

Verdict: PASS

Reproduce: run the five commands above from the repo root; to see the budget on a real build, `bash scripts/size-budget "$(NO_INSTALL=1 bash integrations/build-safari.sh | tail -1)"` (exits 1 until the other nodes land).

## Negative control

Run after the code commit; each break was reverted with `git checkout`.

| Break | Command | Result |
|---|---|---|
| App budget raised to 99 MB in `scripts/size-budget` | `bash tests/size-budget-test.sh` | exit 1, FAIL "2.1 MB app fails and names the biggest file" |
| The old 127 KB cdnjs `highlight.min.js` put back | `node tests/hljs-bundle-test.js` | exit 1, FAIL "dockerfile is registered" and "bundle is under 100000 bytes (127496)" |
| `swift` dropped from the `scripts/hljs-build` language list, bundle rebuilt | `node tests/hljs-bundle-test.js` | exit 1, FAIL "swift is registered" |

The old bundle had no dockerfile grammar, so a dockerfile fence showed unhighlighted; the new build adds it.
