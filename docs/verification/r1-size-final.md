# Proof of Done, r1-size-final

The release app is 2,208,095 bytes and its DMG 1,233,954 bytes (arm64, Developer ID signed, as `scripts/release.sh` builds it). The budget is now set from that, and `scripts/release.sh` fails when the app or the DMG grows past it.

| Number | Before | After | How measured |
|---|---|---|---|
| App, headless build (adhoc), arm64 | 2,500,081 (wave join: 2,500,001) | 2,171,852 | `scripts/size-budget` on `NO_INSTALL=1 bash integrations/build-safari.sh` |
| App, release config (Developer ID, `SKIN_CSS=` blank, CLI bundled) | not measured | 2,208,095 | same build as `release.sh` runs, no notarize, no publish |
| DMG, release config (`hdiutil create -volname Spacedown -srcfolder <stage with app + /Applications> -fs HFS+ -format UDZO`, then `codesign`) | 1,493,942 (wave join, headless) | 1,233,954 to 1,234,082 | `stat -f %z` |
| DMG, plain `hdiutil create -srcfolder <app> -format UDZO` (default filesystem, not what `release.sh` makes) | | 1,516,321 | `stat -f %z` |
| App, universal (arm64 + x86_64), for reference | | 2,683,231; DMG 1,403,996 unsigned | a one-off build with `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` added to the xcodebuild settings, then reverted |
| Budget | app 2,000,000, dmg 1,000,000 | app 2,300,000, dmg 1,300,000 | measured size rounded up to the next 0.1 MB |

`release.sh` builds arm64 only: it never sets `ARCHS`, and `xcodebuild` picks the first destination (this arm64 host). A release made on this host does not run on an Intel Mac. Going universal is a decision for a human; it needs the budget raised to about 2.7 MB and 1.5 MB.

## What changed

| Change | Effect |
|---|---|
| `integrations/build-safari.sh`: `DEPLOYMENT_POSTPROCESSING`, `STRIP_INSTALLED_PRODUCT`, `COPY_PHASE_STRIP`, `STRIP_STYLE=all`, `DEAD_CODE_STRIPPING`, `DEBUG_INFORMATION_FORMAT=dwarf` on both xcodebuild calls | Spacedown binary 699,472 to 326,272, SpacedownQL 135,584 to 103,216; local symbols 2,878 to 587 and 205. Headless and release builds both strip. Set on the command line, not in `project.yml` (frozen) or the pbxproj (frozen). |
| One KaTeX 0.19.0: the extension's `katex.min.js` and `katex.min.css` are now the 0.19.0 files (they were 0.16.11, while the CLI paired that CSS with 0.19.0 fonts) | script, stylesheet and fonts are one version, in a checkout and in the app |
| `scripts/build-ql-katex` embeds the 20 woff2 fonts in the stylesheet as data URIs; `build-safari.sh` ships that file in the extension | the panel has fonts at all (its relative `url(fonts/...)` never resolved with no base URL) and the bundled CLI reads the same file |
| `scripts/bundle-cli` leaves out `assets/katex/fonts` (and now `--delete-excluded`, so a rebuilt app does not keep a stale copy) | the CLI inside the app carries no KaTeX bytes, 261 KB fewer |
| `MarkdownPreviewProvider.swift` CSP: `font-src data:` added | without it the panel blocks every font data URI, KaTeX and iA Writer alike (24 blocked loads in a headless run with the panel's own CSP). `data:` reaches nothing off the machine. This is a frozen file and a guardrail edit: review it. |
| `scripts/size-budget` defaults 2.3 MB and 1.3 MB; `scripts/release.sh` runs it after the build (before notarizing), after the DMG is signed, and on the store build | a release fails when the app or the DMG grows |
| `tests/smoke.sh` (frozen), three edits: the bundle section no longer requires the KaTeX fonts in the CLI (it must lack them) and stages the extension's embedded stylesheet; the equation-number checks look for `katex-tag` (0.19.0 names the class that way, 0.16.11 used `tag`) | needed by the design change and the version bump |
| `tests/katex-one-test.sh`, `tests/fixture/math-fonts.md` | version pin, embed step, and the font check for both pages |

Net size against the wave join estimate: the estimate (1,825,782) dropped the CLI fonts without adding any to the extension. The extension has to carry them for the panel to draw math, so the stylesheet grows from 23,335 to 368,894 bytes and the app lands at 2,171,852 (headless).

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `NO_INSTALL=1 bash integrations/build-safari.sh` (headless), then `scripts/size-budget <app>` | 0 | PASS, 2,171,852 of 2,300,000 |
| `SKIN_CSS= SIGN_ID=<Developer ID> NO_INSTALL=1 bash integrations/build-safari.sh`, DMG as `release.sh`, `scripts/size-budget <app> <dmg>` | 0 | PASS, app 2,208,095, dmg 1,234,082; `codesign --verify --deep --strict` ok |
| `bash tests/smoke.sh --only bundle,katex,cli,quicklook,notary,shot` | 0 | PASS, 68 checks |
| `bash tests/katex-one-test.sh <app>` | 0 | PASS, 11 checks: panel page and CLI page each typeset 14 formulas, 14 KaTeX font faces loaded, 0 failed, 0 KaTeX errors; the panel CSP blocks no font |
| `bash tests/size-budget-test.sh` | 0 | PASS, 5 checks |
| node `test-render`, `test-contract`, `test-boxdraw`, `test-xray`, `test-present`, `tests/hljs-bundle-test.js` | 0 | PASS |
| `bash tests/smoke.sh` (full suite, once, at the end) | 0 | PASS, 164 checks |

Screenshots of the math fixture (`tests/fixture/math-fonts.md`: every KaTeX family, large delimiters, matrices), both showing typeset math with KaTeX glyphs and no fallback letterforms:

- Panel page builder (same head order and CSP as `buildPreviewHTML`, extension resources): `docs/verification/r1-size-final/panel-math.png`
- CLI, `spacedown --offline --shot`: `docs/verification/r1-size-final/cli-math.png`

## Negative control

Run after the code was committed; each break was reverted with `git checkout`.

| Break | Command | Result |
|---|---|---|
| `STRIP_SETTINGS` turned off in `build-safari.sh` (symbols left in) | `NO_INSTALL=1 bash integrations/build-safari.sh`, then `bash scripts/size-budget <app>` | exit 1: `FAIL app is 277420 bytes over budget` (2,577,420; Spacedown binary 699,472) |
| `font-src data:` removed from the panel CSP | `bash tests/katex-one-test.sh` | exit 1: `the panel CSP blocks 20 embedded font load(s)` |
| `--exclude katex/fonts` removed from `scripts/bundle-cli` | `bash tests/smoke.sh --only bundle` | exit 1: `should be absent: assets/katex/fonts/KaTeX_Main-Regular.woff2`, `bundled layout incomplete` |

## Not proven

- The Finder Quick Look panel itself was not exercised (a live panel is not reachable headless). The panel check uses the page `buildPreviewHTML` assembles, in headless Chromium, with the panel's own CSP; WebKit's enforcement of that CSP in the Quick Look host is assumed to match.
- The stripped binaries were not launched: the build only verifies the signature. A stripped Mach-O keeps the symbols dyld and the ObjC runtime need; run the app and press space on a `.md` once before shipping.
- Notarization and stapling add a ticket (a few KB) to the app and the DMG; the 0.1 MB rounding is the room for it. The stapled sizes were not measured because nothing was notarized.
- The pandoc-era files (`assets/katex/katex.min.js`, `katex.min.css`, `embed-images.py`, `inline-katex.py`, `eq-labels.py`, `tsv-tables.py`, `frontmatter-to-table.py`, `callouts-to-html.py`, `details-summary.py`) are left for the owner. `assets/katex/katex.min.js` and `.css` are now duplicates of the extension's files and nothing reads them.

## Rollback

Revert the squash commit: the app returns to 0.16.11 KaTeX in the extension with no fonts in the panel, symbols in the binaries and the 2 MB / 1 MB budget.

## Recorded run

```
Command: bash scripts/size-budget <release app> <release dmg>   (Developer ID build, dmg as release.sh makes it)
Exit: 0
Output:
  size-budget: app 2208095 bytes (budget 2300000)
  size-budget: dmg 1234082 bytes (budget 1300000)
  size-budget: ok

Command: bash tests/katex-one-test.sh <release app>
Exit: 0
Output:
  [1] one version
    ok   katex.min.js is 0.19.0
    ok   THIRD_PARTY_NOTICES names 0.19.0 once for script, stylesheet and fonts
    ok   the stylesheet names 20 woff2 fonts, all in assets/katex/fonts, none extra
  [2] build-ql-katex
    ok   20 fonts embedded as woff2 data URIs, no relative url, no woff or ttf left
    ok   the app's extension ships exactly that stylesheet
    ok   the bundled CLI carries no KaTeX script, stylesheet or font file; the app has no loose font
  [3] the panel page and the CLI page draw the math with the fonts
    ok   panel page: 14 formulas typeset, 14 KaTeX font faces loaded (11 families used), 0 failed, 0 KaTeX errors
    ok   spacedown --offline --shot wrote <shots>/cli-math.png, no katex warning
    ok   CLI page: 14 formulas typeset, 14 KaTeX font faces loaded (11 families used), 0 failed, 0 KaTeX errors
    ok   panel screenshot: <shots>/panel-math.png
    ok   the panel's own CSP (read from MarkdownPreviewProvider.swift) lets every embedded font load
  katex-one-test: 11 passed, 0 failed

Command: bash tests/smoke.sh   (full suite)
Exit: 0
Output:
  smoke: all 164 passed
Verdict: PASS
```
