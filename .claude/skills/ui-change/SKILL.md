---
name: ui-change
description: Change what Spacedown shows: the Quick Look panel, the CLI page, a theme, a font, the reading chrome, the settings window or onboarding. Use for any edit to rendered output or to a screen. Covers the render tests, layout checks, screenshots under docs/verification/<slug>/ and the live panel check in a VM or a clean macOS user.
---

# Change the UI

CI never opens the real Quick Look panel, so your screenshots and notes in the PR are the only proof of what a user sees. Test tiers: `docs/dev/testing.md`. The proof rules: `AGENTS.md`, "Proof of done".

## 1. Know what runs where

The Finder panel renders an HTML string with JavaScript off. Render-time hooks work there; page-time hooks (`init`, `key`, `print`, `reset`) do not. Read `docs/contract-r1.md`, "Read this first", before you design a feature around a key press or a script. If your change needs a frozen file, stop: it goes through a `contract/<slug>` PR and a maintainer.

## 2. Iterate on the render core

```sh
node integrations/safari/quick-look/test-render.js
spacedown tests/fixture/fixture.md          # the CLI page, to look at by eye
bash tests/smoke.sh --only quicklook,render
```

- `tests/fixture/fixture.md` exercises every feature. Add a case there when you add a feature.
- The CLI page and the Finder panel share the render core but not the page shell. A look that is right in the browser can be wrong in the panel.

## 3. Check the layout

```sh
scripts/layout-check <file.md>
scripts/layout-check --dark <file.md>
```

It renders at 390, 768, 1470 and 1728 px, prints one line per width, writes a screenshot per width, and exits 1 when any width scrolls sideways. It needs a Chromium-family browser (`BROWSER` picks one). It uses a private profile and never touches your running browser.

## 4. Screenshots go in the PR

- Make a folder `docs/verification/<slug>/`, where `<slug>` is the name of your proof file. Name files `<what>-before.png` and `<what>-after.png`. Take the before on `origin/main`.
- Link each image from the proof file by a relative path, and show the before and after in the PR body (the PR template's Demo section).
- Keep images small (`pngquant` or a crop). Never commit `build/` or a rendered `.html`.
- A CLI screenshot can come from `spacedown <file.md> --shot out.png --offline`. A panel screenshot has to come from step 5.

## 5. The live Quick Look panel: never on a daily-use Mac

```sh
integrations/build-safari.sh          # installs and registers the app: a VM or clean user only
qlmanage -r; qlmanage -r cache
qlmanage -p <file.md>                 # or press space on the file in Finder
```

- `integrations/build-safari.sh` without `NO_INSTALL=1` installs `Spacedown.app` into `~/Applications` and registers the extension on that account. Run it in a macOS VM or a clean macOS user account created for the test. A throwaway account is enough; delete it after.
- On your own Mac use `NO_INSTALL=1 integrations/build-safari.sh`: it builds and signs ad hoc and installs nothing.
- Say in the proof file where you ran it (a VM, a clean user) and the macOS version. If you could not run it, say that in the PR Notes and do not claim the panel looks right.

## 6. Finish

Follow `ship-pr` for the proof file, `bash scripts/check.sh`, the PR and CI. The proof file holds a `Command:` / `Exit:` / `Output:` / `Verdict:` block for each test you ran, a negative control (break the rule you changed, show the render test go red, restore), and the screenshots by link.

## Done when

The render tests and `bash scripts/check.sh` exit 0, `scripts/layout-check` exits 0 for your fixture, before and after screenshots sit under `docs/verification/<slug>/` and are linked from the proof file, and the live panel was checked in a VM or a clean macOS user (or the PR says it was not).
