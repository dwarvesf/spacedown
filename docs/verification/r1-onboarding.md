# Proof of Done, r1-onboarding

A first-launch window in `Spacedown.app` (`Onboarding.swift`): a three-row checklist, "Preview a sample" through the system Quick Look panel on `Resources/Sample.md`, and a three-step troubleshooter. It is reachable again from Help, "Welcome to Spacedown". The app is sandboxed and cannot read the Quick Look switch, so the window never shows an on or off status of its own: row 1 reads "Check with the sample", the panel is the proof, and the person answers.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh --only quicklook,bundle` | 0 | PASS (11 passed) |
| `NO_INSTALL=1 bash integrations/build-safari.sh` | 0 | PASS |
| `node integrations/safari/quick-look/render-file.js integrations/safari/SpacedownDrop/SpacedownDrop/Resources/Sample.md` | 0 | `callouts:1 katex:3 leaked-placeholders:0` |
| headless launch of the built app with `SPACEDOWN_ONBOARDING_STATE=<state>`, `screencapture -l <window>` | 0 | every state, light and dark, in `docs/verification/r1-onboarding/` |

The same hooks open the real panel (`SPACEDOWN_ONBOARDING_PANEL=1`). In the capture, Quick Look renders `Sample.md` with Spacedown's reading theme (table, typeset `E = mc^2`, callout) from inside the sandboxed app: `quicklook-panel-light.png`, `quicklook-panel-dark.png`.

## What a sandboxed app can and cannot do (measured in the sandbox)

| Need | Result |
|---|---|
| Is the Quick Look extension on? | Not detected. `pluginkit` is not usable from the sandbox. The window says "Check with the sample". |
| List apps with a Markdown Quick Look preview | Works for `/Applications` and `/System/Applications` (reads each appex `Info.plist`). `~/Applications` is invisible, and the window says so. If no extension is readable at all the window says it could not read the list, never "none found". |
| Run `qlmanage -r` | Not attempted. The window shows the command with a Copy button and "Finder may need a relaunch". |
| System Settings pane | `x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview`, the URL the existing window already uses. The Login Items & Extensions settings extension in this macOS carries the strings `x-apple.systempreferences:com.apple.ExtensionsPreferences?` and `extensionPointIdentifier`. Not clicked; the base pane is the fallback if the open fails. |

## Negative control

Run after the commit. A copy of `Sample.md` without its inline math and callout, through the same render command:

```
Sample.md: ... callouts:0 ... katex:0 ...
```

Also seen while building: the first build failed with "missing import of defining module 'Combine'" until the import was added, so the build check does bite.

## Not verified

- A click on any button. No input is sent to the live Mac. The answer buttons, Copy and the System Settings link were read, not pressed.
- The Safari row states "On" and "Off". The build here has no Safari extension, so only "Not included in this build" was captured.
- A fresh install with the real App Group. The adhoc build with the group entitlement hung at sandbox start-up (stack in `libsecinit`, cause not isolated; another node's build of the same bundle id was running), so the screenshots come from a copy of the built app with its own bundle id, no extensions and no group. The panel renders through the already installed Quick Look extension.

## Rollback

Revert this commit. `Onboarding.start()` goes back to a no-op, and `Sample.md` is the stub.
