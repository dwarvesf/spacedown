# Proof of Done, onboarding-fits-screen

The "Welcome to Spacedown" window (`Onboarding.swift`) is about 600 points tall. It was centered before SwiftUI had sized it, and a later resize grows a window down from its top-left corner, so on a 1280x720-point screen it landed low and off center, and the Done button sat under the Dock. The window now stays inside the screen's visible frame: its content height is capped at the visible height minus the title bar, taller content scrolls, and it is positioned again after every resize and once more when layout has settled.

All screenshots are of the real built app, in the mac-ui VM, opened from Help, "Welcome to Spacedown", with real clicks over VNC. The images are cropped to the window and the screen edge it must clear; nothing else was edited.

## Green run

| Screen (points) | How it was set | Result | Screenshot |
|---|---|---|---|
| 1280x720 (the VM's default: 2560x1440 pixels at 2x) | none, the VM's own mode | whole window between the menu bar and the Dock, centered, Done visible | [after](onboarding-fits-screen/after-1280x720.png) |
| 1280x720, click Done | VNC click on Done | the window closes | [after](onboarding-fits-screen/after-1280x720-done-clicked.png) |
| 2560x1440 (normal size, 1x) | display mode 22 | window hugs its content, centered, no blank space | [after](onboarding-fits-screen/after-2560x1440.png) |
| 1024x576 (shorter than the content) | display mode 11 | window capped to the screen, scrollbar shown | [top](onboarding-fits-screen/after-1024x576-top.png) |
| 1024x576, scrolled to the end | click in the scroll track | Done reachable | [scrolled](onboarding-fits-screen/after-1024x576-scrolled.png) |
| 1024x576, click Done | VNC click on Done | the window closes | [closed](onboarding-fits-screen/after-1024x576-done-clicked.png) |

```
Command: NO_INSTALL=1 bash integrations/build-safari.sh
Exit: 0
Output: build-safari: signing (- + runtime + entitlements)...  .../Release/Spacedown.app
Verdict: PASS
```

```
Command: bash tests/smoke.sh --only quicklook,bundle
Exit: 0
Output: smoke: all 11 passed
Verdict: PASS
```

## Negative control

The base commit (no fix) built the same way and run in the same VM at the same 1280x720-point mode, same steps: [before](onboarding-fits-screen/before-1280x720.png). The window is placed low and right of center, well below where the fixed window starts, and the Done row is under the Dock.

```
Command: build the base commit, open Help, Welcome to Spacedown at 1280x720 points, screenshot
Exit: 0
Mutation: none needed, the unfixed code is the control
Output: Done button not on screen; window bottom under the Dock
Restore: the fixed build, same steps: Done visible, window inside the visible frame
Verdict: RED, as expected (before-1280x720.png), GREEN after the fix (after-1280x720.png)
```

An intermediate version of the fix (a `ViewThatFits` with an ideal height of the screen cap) also fit at 1280x720 but stretched the window to the full cap on a taller screen, with blank space above the content: seen at 2560x1440 and replaced by the measured-height version above. That screenshot is not kept.

## Reproduce

1. Build the base and the fixed tree with `NO_INSTALL=1 integrations/build-safari.sh`; zip each `Spacedown.app` into the VM share (`~/vm-share`) and unzip it into a scratch directory in the guest.
2. Run `mac-ui-run` on a scratch git repo with a command that launches `Spacedown.app/Contents/MacOS/Spacedown` and waits for a stop file (the app dies with the job, and `mac-ui-run` removes its guest copy of the repo, not the app directory).
3. Click the Spacedown window, Help, Welcome to Spacedown, with `mac-ui-vnc click`, and `mac-ui-vnc shot`.
4. The guest's default mode is 1280x720 points at 2x. To change it for a shot, run `swift setmode.swift <mode id>` through `mac-ui-run` (the guest has `swiftc`), where `setmode.swift` calls `CGBeginDisplayConfiguration`, `CGConfigureDisplayWithDisplayMode` and `CGCompleteDisplayConfiguration(.forSession)` on the mode whose `ioDisplayModeID` is wanted (13 default 1280x720 at 2x, 22 is 2560x1440 at 1x, 11 is 1024x576 at 1x; list them with `CGDisplayCopyAllDisplayModes`). A plain `CGDisplaySetDisplayMode` call reverts when the process exits. Restore mode 13 afterward.
