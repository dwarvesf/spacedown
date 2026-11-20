# Release 1 contract

Node 0 of release 1. The seven feature nodes code against this file only. A change to a frozen file goes through a contract PR first, never inside a feature PR.

## Read this first: the Finder panel runs no scripts

The Quick Look extension is data-based (`QLIsDataBasedPreview`). It hands Quick Look an HTML string, and Quick Look renders that HTML with JavaScript off. The page CSP (`default-src 'none'`) blocks scripts too. Third-party extensions report the same limit; this repo has not tested it in a live panel.

| Hook kind | Where it runs |
|---|---|
| Render time (`transform`, `css`, `controls`, `toolbar`) | everywhere: the appex (JavaScriptCore), node tests, the CLI (`osascript -l JavaScript`) |
| Page time (`init`, `key`, `print`, `reset`) | only in a page that runs scripts and calls `SD.boot`. The Finder panel does not run them. The CLI page can, once C1 wires it. |

Consequences:

- Q3 X-ray works in the panel with no JS. Mark the text at render time (`transform`). Toggle with a CSS checkbox: `controls` emits `<input type="checkbox" id="sd-xray" hidden>` as a body-level sibling before the content, `toolbar` emits `<label for="sd-xray">`, and the CSS uses `#sd-xray:checked ~ * .your-mark`. The deployment target is macOS 13.0, so `:has()` is available; regex lookbehind is not (JavaScriptCore has it from macOS 13.3).
- Q4 Present needs page time: P, the arrows and Esc are key events. In the Finder panel it is blocked until the appex becomes a view-based preview with its own `WKWebView` (an architecture change, a human call). In that panel Esc also closes Quick Look. Build Q4 against `SD.boot` and test it in node and in the CLI page.

## Load order

`integrations/safari/quick-look/Resources/load-order.txt` is the only list. The appex (`MarkdownRenderer`), node (`load-core.js`) and the CLI under osascript read it.

```
marked.min.js  katex.min.js  highlight.min.js  ql-render.js  boxdraw.js  xray.js  present.js
```

A new plug-in file goes into this list through a contract PR. An osascript host loads each file with `(0, eval)(text)`, in order; smoke check 39c shows how.

## Host API (`ql-render.js`, global `SD`)

| Call | Returns | Notes |
|---|---|---|
| `SD.render(src, settings)` | `{ body, css, chrome, attrs, config }`, all strings except `config` | DOM-free. `settings` is any partial object, validated by `SD.config`. |
| `SD.config(partial)` | the full settings object | defaults, plus every valid key of `partial`. Unknown keys and wrong types are dropped, ints are clamped, `0`/`1` count as booleans. Adds `surface` (`quicklook` default, `cli`, `app`, `test`). |
| `SD.boot(document, settings)` | `config` | page time: calls every `init`, adds one `keydown` listener, runs every `print` on `beforeprint` |
| `SD.reset(document, settings)` | none | calls every `reset` |
| `SD.register(plugin)` | `plugin` | replaces an earlier plugin with the same `id`; throws on a missing `id` |
| `SD.plugins()` / `SD.plugin(id)` | ids in run order / the plugin or `null` | |
| `SD.errors` | array of `"<id>.<hook>: <message>"` | a hook that throws is skipped, and the render goes on |
| `SD.DEFAULTS`, `SD.ENUMS`, `SD.RANGES` | the settings table below | read only |
| `mdToHtml(src, settings)` | body HTML | kept for old callers; runs the `transform` hooks |

Every host builds the page in this order:

```
<html lang="en" {attrs}>
<head> CSP, panel reset, katex.min.css, md-style.html, hljs-theme.css, ql-reading.css, ql-settings.css, <style>{css}</style> </head>
<body>{chrome}{body}</body>
```

The appex does this in `buildPreviewHTML`, and `preview-skin.sh` does the same in node. `attrs` = `data-sd-theme`, `data-sd-appearance` and `data-sd-outline`, plus `style="--ql-size:<textSize>px"`. `chrome` = every plugin's `controls`, then `<div class="sd-ql-toolbar" role="toolbar">` with every `toolbar` item; it is empty when there are no items. When a toolbar exists, `css` starts with the core toolbar CSS (fixed top right, hidden in print).

## Plug-in hooks

```js
SD.register({
  id: "xray",          // required, unique
  order: 100,          // lower runs first; boxdraw 10, xray 100, present 200
  // render time: DOM-free, return a string, never touch document
  transform(html, cfg) { return html; },  // full body HTML after the core passes (frontmatter table included)
  css(cfg)       { return ""; },          // CSS text; the host wraps it in <style>
  controls(cfg)  { return ""; },          // body-level HTML placed before the content (checkbox toggles)
  toolbar(cfg)   { return ""; },          // items inside the shared toolbar (labels, buttons)
  // page time: only under SD.boot
  init(doc, cfg)  {},                     // after load
  key(ev, cfg)    { return false; },      // true = handled: preventDefault, and later plugins are not asked
  print(doc, cfg) {},                     // on beforeprint: leave a printable page
  reset(doc, cfg) {}                      // back to the plain reading page
});
```

`key` never sees keys pressed with Cmd, Ctrl or Alt held, or keys typed into an input, textarea, select or editable element. The browser chrome (`assets/reading-chrome-foot.html`) already binds `s`/`S`, `[` and, in RSVP mode only, the arrows, Space, Esc, Home and End. P is free.

## Settings

| Key | Type | Default | Allowed |
|---|---|---|---|
| `theme` | string | `"ia"` | `ia` `tm` `paper` `read` `mono` (the CLI `--font-mode` names) |
| `appearance` | string | `"system"` | `system` `light` `dark` |
| `textSize` | int (px) | `18` | 12 to 32 |
| `outlineDefault` | string | `"auto"` | `auto` (window width decides, as today) `open` `closed` |
| `xrayEnabled` | bool | `false` | X-ray on when a page opens |
| `xrayDashes` | bool | `true` | mark em and en dashes |
| `xrayLongSentences` | bool | `true` | mark sentences over `xraySentenceWords` |
| `xraySentenceWords` | int | `25` | 8 to 80 |
| `xrayFillers` | bool | `true` | mark words from `xrayFillerWords` |
| `xrayFillerWords` | [string] | `very, really, just, actually, basically, simply, quite, rather, somewhat, literally, obviously, clearly, of course, in order to` | entries are trimmed, and empty entries are dropped |
| `xrayTicketIds` | bool | `true` | mark ticket and spec IDs; the pattern lives in `xray.js` |

Source of truth: `SD.DEFAULTS` in `ql-render.js`. `integrations/safari/shared/SpacedownSettings.swift` mirrors it, and `test-contract.js` fails if they drift.

### Storage and readers

- Store: the App Group defaults suite `W777S7V8TN.dfoundation.spacedown`. It uses the macOS team-prefixed form, so it needs no provisioning profile entry. Both the app and the Quick Look extension carry `com.apple.security.application-groups` with this id.
- App (A2) writes: `SpacedownSettings.store.set(value, forKey: key)`. Use the key names above.
- Extension reads: `buildPreviewHTML` passes `SpacedownSettings.stored()` (only the keys that are set) to `SD.render` on every preview, so a change shows on the next spacebar press.
- CLI reads: `scripts/sd-settings` prints the stored keys as JSON, or `{}`. C1 passes that output, plus `"surface":"cli"`, to `SD.render`. The CLI keeps no copy of the defaults. `SPACEDOWN_PREFS=<plist>` overrides the path. The script reads the plist file directly, so a write from the last few seconds can lag.
- Debug builds (`build-safari.sh` with `CONFIG=Debug`) use the group `W777S7V8TN.dfoundation.spacedown.dev`, so a test build never reads or writes the installed release's settings. `scripts/sd-settings` reads the release group.
- Adhoc builds (`build-safari.sh` with no `SIGN_ID`) have no team, so the group is not granted. The extension then reads its own empty defaults and renders with the defaults. A2 can test end to end only with a Developer ID or Apple Distribution build.

## File ownership

Paths are relative to `integrations/safari/quick-look/` (QL), `integrations/safari/SpacedownDrop/SpacedownDrop/` (APP) or the repo root.

| Node | Owns (edit freely) | Smoke sections to run |
|---|---|---|
| Q1 box diagrams + fonts | QL `Resources/boxdraw.js`, QL `test-boxdraw.js`, `scripts/build-ql-skin`, `scripts/ia-fontface-css`, `assets/fonts/ia/**` | `quicklook,fonts,render` |
| T1 size trim | QL `Resources/highlight.min.js` (plus any script that builds it), `integrations/build-safari.sh`, `scripts/release.sh`, `integrations/safari/make-appicon.swift`, APP `Assets.xcassets/AppIcon.appiconset/**` | `quicklook,render,bundle,notary,katex` |
| C1 CLI on the QL core | `bin/spacedown` (HTML path), `scripts/bundle-cli`, new CLI-side files under `scripts/` or `assets/` | full suite |
| Q3 X-ray | QL `Resources/xray.js`, QL `test-xray.js` | `xray,quicklook` |
| Q4 Present | QL `Resources/present.js`, QL `test-present.js` | `present,quicklook` |
| A2 Settings window | APP `SettingsWindow.swift`, QL `Resources/ql-settings.css` | `quicklook,bundle`, plus a build |
| A1 + A1b onboarding | APP `Onboarding.swift`, APP `Resources/Sample.md` | `quicklook,bundle`, plus a build |

Build check for any Swift or bundle change: `NO_INSTALL=1 bash integrations/build-safari.sh`. It runs headless, leaves the installed app alone and prints the built app path.

Each app node gets one Swift file, already in the Xcode project. Keep new types in that file: a second file means a `project.pbxproj` edit, which is frozen. `AppDelegate.applicationDidFinishLaunching` already calls `SettingsWindow.install()`, then `Onboarding.start()`. Add a menu item from inside your own file.

### Shared and frozen (contract PR only)

QL `Resources/ql-render.js`, QL `Resources/load-order.txt`, QL `Sources/MarkdownPreviewProvider.swift`, QL `load-core.js`, QL `test-contract.js`, QL `test-render.js`, QL `render-file.js`, QL `preview-skin.sh`, QL `project.yml`, QL `Info.plist`, `integrations/safari/shared/SpacedownSettings.swift`, all `*.entitlements`, `SpacedownDrop.xcodeproj/project.pbxproj`, APP `AppDelegate.swift`, `scripts/sd-settings`, `tests/smoke.sh`, `assets/vscode-preview-head.html`, QL `Resources/ql-reading.css` (except one rule Q1 may add: the box-drawing `pre` line-height, if a class from `boxdraw.js` cannot carry it through the `css` hook), this file.

Append-only for every node: `tests/known-failures.txt` (one line per check that is red on purpose; the format is in the file header). Remove your line when the check goes green.

## Operator steps (Apple Developer)

- None expected. A team-prefixed App Group (`W777S7V8TN.…`) is authorized by the team ID in the signature, for Developer ID and for Mac App Store signing.
- If Mac App Store upload validation rejects the group: enable the App Groups capability on the bundle IDs `dfoundation.spacedown` and `dfoundation.spacedown.quicklook`, register the group, then regenerate both profiles with `scripts/asc_setup.py`.
