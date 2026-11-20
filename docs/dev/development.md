# Development

How the parts fit, how to build each one, and where the code lives. Setup from a fresh clone: [CONTRIBUTING.md](../../CONTRIBUTING.md). Tests: [testing.md](testing.md).

## How it works

```
 Finder, space bar                     a shell                       an agent (MCP client)
        │                                │                                 │
        ▼                                ▼                                 ▼
 Spacedown.app                        bin/spacedown (bash)  ◄──────  spacedown mcp
   SpacedownQL.appex (Swift)            │  assets/sd-cli-render.js      assets/sd-mcp.js
   MarkdownPreviewProvider              │  under osascript -l JavaScript under osascript
   JavaScriptCore                       │
        │                               │
        └──────────────┬────────────────┘
                       ▼
        render core: integrations/safari/quick-look/Resources/
        marked + KaTeX + highlight.js + ql-render.js + plug-ins
        (boxdraw.js, xray.js, present.js), loaded in load-order.txt order
                       │
                       ▼
        HTML: Quick Look skin (ql-reading.css) in the panel,
              a self-contained page with the reading chrome in a browser
```

- One render core serves both surfaces. The Quick Look panel runs no scripts (it is a data-based preview with a strict CSP), so everything the panel shows is in the HTML the core returns. `docs/contract-r1.md` states the contract and which files it freezes.
- The CLI is a bash script. It renders with the same core under `osascript`, so it needs macOS but no Node, pandoc or Python for HTML. `spacedown docx` uses pandoc with `assets/docx/ia-reference.docx`, or `textutil` without pandoc.
- `spacedown mcp` is a stdio MCP server (`render`, `shot`, `lint`) that calls the CLI.
- The Safari drop extension is opt-in. It is sandboxed, so it hands each dropped file over XPC to an unsandboxed helper (`integrations/safari/helper/`) that runs the CLI.

## Build

| What | Command | Output |
|---|---|---|
| The app, Quick Look only, not installed | `NO_INSTALL=1 integrations/build-safari.sh` | prints the path of the built `Spacedown.app` |
| Also the Safari extension and its helper | `NO_INSTALL=1 integrations/build-safari.sh --with-safari` | same |
| Build and install | `integrations/build-safari.sh` | `~/Applications/Spacedown.app`, registered and opened once |
| A test build beside an installed release | `CONFIG=Debug integrations/build-safari.sh` | `~/Applications/Spacedown Dev.app`: every id, the App Group and the helper service carry `.dev`, so it never touches the release |
| The Quick Look skin with the iA fonts embedded | `scripts/build-ql-skin [out.css]` | the shipped `ql-reading.css` |
| KaTeX for the panel | `scripts/build-ql-katex` | KaTeX CSS with the fonts inlined |
| The custom highlight.js | `scripts/hljs-build` | `Resources/highlight.min.js` |
| The CLI copy inside the app | `scripts/bundle-cli` (run by the build; `BUNDLE_CLI=0` skips it) | `Contents/Resources/cli/` |

Every build is universal (arm64 and x86_64) with a macOS 13.0 deployment target. The build signs ad hoc, so Gatekeeper and Safari treat a local build as unsigned. The header of `integrations/build-safari.sh` lists every variable (`SIGN_ID`, `NOTARIZE`, `APP_DEST`, `SKIN_CSS`, `CONFIG`, ...). Signing with a real identity is a maintainer step ([release.md](release.md)).

The Quick Look Xcode project is generated from `integrations/safari/quick-look/project.yml` by XcodeGen on every build; do not commit the generated `.xcodeproj`.

## Project layout

```
bin/spacedown                     the CLI (bash)
assets/                           CLI page parts: themes, reading chrome, KaTeX, fonts, the docx reference
  sd-cli-render.js, sd-mcp.js     the CLI render entry and the MCP server
  REFRESH.md                      where the vendored stylesheet and highlight.js come from
integrations/
  build-safari.sh                 builds, signs and installs the app
  safari/quick-look/              the Quick Look extension: Swift source, render core (Resources/), its node tests
  safari/SpacedownDrop/           the container app and the Safari drop extension (Xcode project)
  safari/shared/                  settings code shared by the app and the extension
  safari/helper/                  the XPC render helper for the Safari extension
  extension/, finder-app/         the Chromium drop extension and the Finder "Open With" app (integrations/README.md)
scripts/                          build helpers, release, screenshots, store listing
tests/                            smoke.sh, unit tests, fixtures (fixture/, fixtures/)
site/                             the landing page
docs/                             this documentation (index: docs/README.md)
```

## Vendored code

KaTeX, marked, highlight.js, the iA Writer fonts and the VS Code preview stylesheet are vendored. Their licenses are in `THIRD_PARTY_NOTICES.md`. Refresh steps: `assets/REFRESH.md`. `tests/katex-one-test.sh` checks that one KaTeX version is used everywhere.
