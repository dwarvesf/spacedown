# Proof of Done, bundle-cli-in-app

`Spacedown.app` now carries the `spacedown` CLI at `Contents/Resources/cli/bin/spacedown`, with `assets/` and `scripts/ia-fontface-css` beside it, so the app and the CLI update together and a Homebrew cask can link one binary. `integrations/build-safari.sh` runs `scripts/bundle-cli` before signing. `BUNDLE_CLI=0` skips it, and the Mac App Store build sets that. No version bump, tag or release is part of this change.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |
| `NO_INSTALL=1 bash integrations/build-safari.sh` (ad hoc signing, no credentials) | 0 | PASS |
| `codesign --verify --deep --strict` on the built app | 0 | PASS |
| built app copied elsewhere, `cli/bin/spacedown --version`, `<md>` render, `docx <md>` | 0 | PASS |

```
[bundle-1] bundle-cli lays out the CLI and every runtime file under Contents/Resources/cli
[bundle-3] the bundled CLI, moved and run through a symlink, renders the same HTML as the repo CLI
  ok: byte-identical page (theme, chrome, frontmatter table, callout)
[bundle-4] the bundled CLI embeds the iA fonts
[bundle-5] the bundled CLI exports .docx in the iA look
smoke: all 85 passed
```

The real build placed 19 files (764K) under `Contents/Resources/cli`. A copy of the built app, run through a symlink away from the checkout, printed `spacedown 1.1.0`, rendered a page with the four iA font faces embedded, and wrote a `.docx` with IBM Plex Sans.

Not verified here: notarization and stapling of the Developer ID build, and the cask `binary` link. Both need the release credentials and a published zip.

## Negative control

`scripts/bundle-cli` with its `ia-fontface-css` copy line removed, same suite:

```
    missing: scripts/ia-fontface-css
  FAIL: bundled layout incomplete
  FAIL: bundled render differs from the repo render or failed
  FAIL: bundled render carries no embedded iA fonts
smoke: 82 passed, 3 FAILED
```

## Rollback

Revert this squash commit. A released app that already carries the CLI keeps it until the next release; remove the cask `binary` stanza in the same step.
