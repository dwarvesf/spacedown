# Implementation notes: onboarding window fits the screen

Only the decisions the brief did not make. The brief: on a 1280x720-point screen the welcome window is taller than the visible screen and Done is off screen.

## Decisions

- **Cause.** `win.center()` ran before SwiftUI had sized the window (`NSHostingController` with `.preferredContentSize` resizes after the first layout, from the top-left corner). The window therefore ended up low and right of center, and its tail went under the Dock. The content itself (about 600 points) fits a 720-point screen once centered; it does not fit shorter ones.
- **Height cap from the screen, not a constant.** `maxContentHeight` is the visible frame height minus the title bar and a 16-point margin, refreshed on every show (so a moved screen or a changed display mode is picked up). Content taller than that scrolls.
- **Content height is measured.** The page sits in a `ScrollView`; a preference key reports its height and the frame is `min(content, cap)`. A `ViewThatFits` with an ideal height was tried first and rejected: it filled the whole cap on tall screens and left blank space.
- **Position after layout.** Every `NSWindow.didResize` clamps the window into the visible frame. A new window is centered while a `recenter` flag is set and once more 0.4 seconds later, when layout has settled. A window that is already on screen is only clamped, never moved to the center.
- **Screenshot hooks keep their anchor, then clamp.** `showForScreenshot` passes `center: false`, sets its top-left anchor (120 points from the left), then clamps. On a screen tall enough the frame is as before; on a short one (1280x720 points) the clamp moves the window up, so a hook frame can differ from the old recipes there.
- **No dependency or interface change.** The CLI, the render core and the frozen contract files are untouched, and so are bundle ids and platform settings.

## Not done

- The main app window ("Spacedown", the About-style window) is also off screen on a 1024x576 display. It is outside this change and was not touched.
- No automated test: the window is AppKit and SwiftUI layout with no seam the smoke suite reaches. The proof is real-click screenshots in the VM.
