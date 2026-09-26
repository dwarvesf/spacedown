# spacedown integrations

Two ways to open a `.md` rendered by `spacedown` without typing the command.

| Integration | Trigger | What happens |
|---|---|---|
| **Finder app** (`Spacedown Opener.app`) | double-click / "Open With" / drag a `.md` onto the app icon | renders via `spacedown`, opens the HTML in a browser tab |
| **Browser extension** (`Spacedown`) | drag a `.md` onto the dropzone tab | reads the file, hands it to a native-messaging host that runs `spacedown`, opens the HTML |

Both go through one shared wrapper, [`spacedown-open`](./spacedown-open), which renders then opens a Chromium browser (Edge first). The wrapper exists because `spacedown` only self-opens the browser from a TTY; these callers are not TTYs.

```
 Finder double-click ─┐
                      ├─► spacedown-open ─► spacedown (pandoc+KaTeX) ─► open -a "Microsoft Edge" out.html
 browser drag-drop ───┘     ▲
   │                        │
   └─ extension dropzone ─► native-host (spacedown-host) ──┘
        (sends file text over native messaging)
```

## Install

```bash
./install.sh                 # Finder app + native host, no default hijack
./install.sh --set-default   # also make Spacedown Opener.app the default .md app
./install.sh --uninstall     # remove app + native host manifests
```

`install.sh` is idempotent. It compiles `Spacedown Opener.app` (injecting the absolute `spacedown-open` path), registers it with LaunchServices, and writes the native-messaging host manifest into every installed Chromium browser's `NativeMessagingHosts/` dir.

### Finish the browser half (one-time, manual)

The extension must be loaded by hand once:

1. Open `edge://extensions` (or `chrome://extensions`).
2. Toggle **Developer mode** on.
3. **Load unpacked** -> select `integrations/extension/`.
4. Confirm the extension ID is `mhifeggicglofancjnjmkgihedkddnpn` (fixed by the `key` in `extension/manifest.json`; the native host's `allowed_origins` is pinned to it).
5. Click the toolbar icon -> a **dropzone tab** opens -> drag a `.md` in. Bookmark `chrome-extension://mhifeggicglofancjnjmkgihedkddnpn/dropzone.html` for one-click access.

## Safari (drag-drop) extension

A third integration lives in `safari/`: a Safari Web Extension (same dropzone UI).
Its sandboxed handler forwards the drop over XPC to an unsandboxed, launch-on-demand
helper (`spacedown-render`) that runs `spacedown-open`. `build-safari.sh` is the single
installer for the native bundle. Quick Look is the default; Safari is opt-in:

```bash
./build-safari.sh                # app + Quick Look appex only, installed to ~/Applications
./build-safari.sh --with-safari  # also the Safari ext + helper/LaunchAgent (needs spacedown + pandoc)
```

After `--with-safari`, enable it once in Safari:

1. **Settings > Developer > Allow unsigned extensions** (adhoc-signed counts as unsigned).
2. **Quit and relaunch Safari** (it only rescans dev extensions at launch).
3. **Settings > Extensions** > tick **Spacedown**.
4. Click its toolbar button -> dropzone tab -> drag a `.md` in (opens in Safari).

**Why the helper exists (the load bug, fixed):** a Safari Web Extension **must** be
App-Sandboxed to load; a sandboxed handler **cannot** `Process`-spawn pandoc. The old
build disabled the sandbox so the handler could spawn `spacedown-open`, which is exactly what
kept the extension from ever loading (absent from `Settings > Extensions`, unregistered
in `pluginkit`). The fix: keep the appex sandboxed (+ adhoc + hardened runtime) and move
the spawn into the unsandboxed helper, reached via a per-user LaunchAgent whose label and
Mach service are both `dfoundation.spacedown.render`. launchd starts it on demand and it
idle-exits after 30 seconds. `quick-look/test-render.js` checks that the plist, the helper,
the extension client and the mach-lookup entitlement all name the same service.

**Caveat (notarization, unchanged):** adhoc is still "unsigned" to Safari, so the
"Allow unsigned extensions" toggle **resets every Safari restart** until the app is
notarized with a Developer ID. The Finder "Open With" path renders in
Safari permanently with no toggle and is the zero-infra fallback.

How Safari differs from Chromium (both share `dropzone.{html,js}`):

| | Chromium | Safari |
|---|---|---|
| Native messaging target | external binary via JSON manifest | sandboxed Swift handler -> XPC helper |
| `sendNativeMessage` | `(host, msg, cb)` | `(msg) -> Promise` (dropzone.js branches on `navigator.vendor`) |
| Sandbox | n/a | appex sandboxed (required); pandoc spawn lives in an unsandboxed XPC helper |
| Install | load unpacked | `build-safari.sh` (adhoc), enable in Settings |

## Default-handler tradeoff

`--set-default` makes double-clicking **any** `.md` render it instead of opening your editor. If you edit `.md` more than you preview, skip it: the app still shows under right-click **Open With > Spacedown Opener**. Revert anytime:

```bash
duti -s com.visualstudio.code.oss net.daringfireball.markdown all   # back to VSCodium
```

## How it's wired (the non-obvious bits)

- **Stable extension ID.** `extension/manifest.json` ships a fixed public `key`, so the unpacked extension always gets ID `mhifeggicglofancjnjmkgihedkddnpn`. That lets the native-host manifest pin `allowed_origins` ahead of time, so the whole thing is reproducible from this repo (no "copy the ID Edge assigned you" step).
- **Text, not path.** A file dropped into a browser exposes only its basename, never the real filesystem path (browser security). So the extension sends the file *content*; the host writes a temp copy and renders that. Fine for markdown (well under the 1MB native-messaging message ceiling).
- **PATH.** GUI/stdio contexts (LaunchServices, native messaging) get a minimal PATH without Homebrew or `~/.local/bin`. Both `spacedown-open` and the host re-export a full PATH so `spacedown` and `pandoc` resolve.
- **Native host is on-demand.** No daemon. Edge spawns `spacedown-host` per message and it exits after replying.

## Rebuild from zero

Everything here is derivable from the repo:

1. `cd integrations && ./install.sh`
2. Load `extension/` unpacked in Edge (steps above).

The compiled `Spacedown Opener.app` is a build artifact (gitignored); `install.sh` regenerates it. The native-host manifests live outside the repo (per-browser support dirs) and are regenerated too.

## Files

| File | Role |
|---|---|
| `spacedown-open` | shared wrapper: render + open browser |
| `finder-app/SpacedownOpener.applescript` | source for the open-handler app (path injected at compile) |
| `extension/manifest.json` | MV3 manifest with the fixed `key` |
| `extension/sw.js` | opens the dropzone as a full tab on icon click |
| `extension/dropzone.{html,js}` | the drop UI + native-messaging call |
| `extension/native-host/spacedown-host` | native-messaging host (Python) |
| `extension/native-host/dfoundation.spacedown.json.template` | host manifest (path + ID filled by install.sh) |
| `install.sh` | wires all of the above; `--set-default`, `--uninstall` |
