# Proof of Done, r1-contract

Node 0 of release 1: the plug-in registry in the Quick Look render core, the App Group settings store, the stub files for the seven feature nodes, and the smoke sections that guard them. Contract: `docs/contract-r1.md`.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` (full, 92 s) | 0 | PASS, `smoke: all 155 passed` (149 before, plus 39b, 39c, 39d, 39e, xray, present) |
| `bash tests/smoke.sh --only quicklook,xray,present` | 0 | PASS, `smoke: all 7 passed` |
| `node integrations/safari/quick-look/test-contract.js` | 0 | PASS, 28 checks |
| `NO_INSTALL=1 bash integrations/build-safari.sh` | 0 | app and appex built headless and signed adhoc, nothing installed |

## The real flow: Swift page builder

The appex code ran outside Quick Look. `swiftc` compiled `MarkdownPreviewProvider.swift` and `SpacedownSettings.swift` with a three-line `main.swift`. The harness wrote `textSize=22`, `xrayEnabled=true` and `theme=paper` to a scratch defaults suite, then called `buildPreviewHTML(md, settings: SpacedownSettings.stored(in: suite))` with the built appex's Resources next to it.

| Check | Result |
|---|---|
| scripts loaded through `load-order.txt` | `tests/fixture/fixture.md` rendered with 3 `class="katex` spans |
| settings reached the page | `<html lang="en" data-sd-theme="paper" data-sd-appearance="system" data-sd-outline="auto" style="--ql-size:22px">` |
| UserDefaults bool bridges as a JS boolean | a probe `controls` hook that writes `checked` only when `cfg.xrayEnabled === true` emitted `<input type="checkbox" id="sd-xray" hidden checked>` |
| chrome placed first in the body | `<body><input ...>` then `<div class="sd-ql-toolbar" role="toolbar" ...>` |
| entitlements in the built bundle | `codesign -d --entitlements` on the app and on the appex: `['W777S7V8TN.dfoundation.spacedown']` |
| new app files compiled | `SpacedownSettings.o`, `SettingsWindow.o` and `Onboarding.o` are in the app target's intermediates; `Sample.md` is in `Contents/Resources` |

## Negative control

Committed first (`592687b`). Then `ql-render.js` line 329, `html = runTransforms(...)`, was replaced so the core no longer called the plug-in `transform` hook.

```
Command: bash tests/smoke.sh --only xray,present
Exit: 1
Output: FAIL: xray suite failed / FAIL: present suite failed; smoke: 0 passed, 2 FAILED
Detail: FAIL: render calls the xray transform with its settings
        FAIL: render calls the present transform
Verdict: RED as expected
```

After `git checkout -- ql-render.js`: `smoke: all 2 passed`.

## Not verified

- A live Finder spacebar preview: this needs the GUI and an installed build. The Swift page builder above is the same code, run headless.
- App Group sharing between the processes: an adhoc build has no team, so the group is not granted. That needs a Developer ID or Mac App Store signed build.
- Whether the data-based Quick Look panel runs JavaScript. Third-party extensions report that it does not, so the contract treats page-time hooks as unavailable in the panel.
