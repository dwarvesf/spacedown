# Proof of Done, console-labs-brand

Spacedown now carries the Console Labs brand (https://console.so) everywhere a user or contributor reads it: LICENSE, README, the site, the privacy policy, the App Store metadata, the app window footer, the app's Info.plist copyright, CONTRIBUTING and the docs. The install line is `brew install --cask consolelabs/tap/spacedown`, and the Swift onboarding uses it too.

The release and App Store Connect scripts carry no team defaults. Signing identities are found in the keychain by `TEAM_ID`, and the password manager vault, item titles, CSR subject, notary profile and review contact come from env vars that stop the script with a clear message when unset. Each script takes `--dry-run`. The app window screenshots are regenerated from the page, and `scripts/store-shots.sh` now composes screenshot 3 too.

## Green run

Tests, in a clean macOS VM with stock `/bin/bash` 3.2:

```
Command: /bin/bash tests/smoke.sh; /bin/bash tests/katex-one-test.sh; /bin/bash tests/size-budget-test.sh; node tests/hljs-bundle-test.js
Exit: 0
Output:
smoke: all 192 passed
katex-one-test: 9 passed, 0 failed
size-budget-test: 5 passed, 0 failed
hljs-bundle-test: all passed
Verdict: PASS
```

App build on the host, nothing installed:

```
Command: NO_INSTALL=1 integrations/build-safari.sh --with-safari
Exit: 0
Output:
<worktree>/integrations/safari/SpacedownDrop/build/Build/Products/Release/Spacedown.app
NSHumanReadableCopyright: © 2026 Console Labs
strings Contents/MacOS/Spacedown: brew install --cask consolelabs/tap/spacedown
Verdict: PASS
```

Script dry runs on the host. Nothing signed, notarized, read from the password manager, or uploaded. The Apple team's legal name in the identity names is shown as `<team legal name>`.

```
Command: scripts/release.sh --mas --dry-run
Exit: 0
Output:
dry run: 1.1.0 (<build>), sign: Apple Distribution: <team legal name> (W777S7V8TN), installer: 3rd Party Mac Developer Installer: <team legal name> (W777S7V8TN), profiles in ~/.local/share/spacedown-signing
dry run: stopping before the build; nothing signed or uploaded
Verdict: PASS (both identities found by TEAM_ID)
```

```
Command: scripts/release.sh --dry-run   (no NOTARY_PROFILE, no NOTARY_KEY)
Exit: 1
Output: release: no notary credentials: set NOTARY_PROFILE to a notarytool keychain profile (xcrun notarytool store-credentials <name>), or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER
Verdict: PASS (no default profile; clear message)
```

```
Command: NOTARY_PROFILE=example-missing-profile scripts/release.sh --dry-run
Exit: 1
Output: release: notary credentials rejected: check NOTARY_PROFILE, or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER
Verdict: PASS (the Developer ID identity was found by TEAM_ID; the check stopped at the next step)
```

```
Command: scripts/release.sh --bogus
Exit: 64
Output: usage: scripts/release.sh [--mas] [--dry-run] [x.y.z]
Verdict: PASS
```

```
Command: scripts/mas-altool.sh --dry-run validate <pkg>   (no env), then with OP_VAULT and ASC_OP_ITEM set, then mode "send"
Exit: 1, 0, 64
Output:
scripts/mas-altool.sh: line 19: OP_VAULT: OP_VAULT unset: name the 1Password vault that holds the App Store Connect API key
dry run: validate <pkg> with the API key item ending "Example API Key" in vault "example-vault"; nothing read or uploaded
usage: mas-altool.sh [--dry-run] validate|upload <pkg>
Verdict: PASS
```

```
Command: python3 -I scripts/asc_setup.py --dry-run   (no env), then with OP_VAULT, ASC_OP_ITEM, MAS_P12_OP_TITLE, CSR_SUBJECT set
Exit: 1, 0
Output:
asc_setup: OP_VAULT unset: name the 1Password vault that holds the App Store Connect API key
dry run: DISTRIBUTION: Apple Distribution: <team legal name> (W777S7V8TN)
dry run: MAC_INSTALLER_DISTRIBUTION: 3rd Party Mac Developer Installer: <team legal name> (W777S7V8TN)
dry run: API key item ending 'Example API Key' in vault 'example-vault'; p12 backup title 'Example p12'
dry run: stopping; nothing read, created or uploaded
Verdict: PASS
```

```
Command: python3 -I scripts/asc_listing.py --dry-run docs/app-store/metadata.json docs/app-store/screenshots/*.png   (no env), then with OP_VAULT, ASC_OP_ITEM, REVIEW_CONTACT_BUNDLE set
Exit: 1, 0
Output:
asc_listing: OP_VAULT unset: name the 1Password vault that holds the App Store Connect API key
dry run: dfoundation.spacedown 1.1.0, metadata docs/app-store/metadata.json (14 keys), 3 screenshot(s)
dry run: API key item ending 'Example API Key' in vault 'example-vault'; review contact from com.example.app
dry run: stopping; nothing read or uploaded
Verdict: PASS
```

Screenshots: `scripts/window-shots.sh` and `scripts/store-shots.sh` in the VM with headless Google Chrome (`BROWSER`). `docs/images/app-window.png` (920x1000) and `docs/app-store/screenshots/3-app.png` (2880x1800) match the old images except the footer, which now reads "© 2026 Console Labs".

## Negative control

The identity lookup must fail when the team does not match.

```
Command: bash scripts/release.sh --mas --dry-run
Exit: 0 (green before the mutation)
Mutation: perl -pi -e 's/TEAM_ID:-W777S7V8TN/TEAM_ID:-ZZZZZZZZZZ/' scripts/release.sh
Exit: 1 (under the mutation)
Output: release: no Apple Distribution identity for team ZZZZZZZZZZ in the keychain (or set MAS_SIGN_ID)
Restore: git checkout HEAD -- scripts/release.sh
Exit: 0 (green after the restore)
Verdict: RED, as expected
```

## What still matches the old brand, and why

The brand grep from the task still finds matches in these files only. Each one is an identifier that breaks something if changed, or a recorded command. The PR body lists them literally.

| Kind | Why it stays |
|---|---|
| Bundle ids of the app and its extensions | existing installs, the App Store record, provisioning profiles |
| The app group id | changing it loses every user's saved settings |
| The XPC helper's launchd label and Mach service | installed Safari helpers look them up by name |
| The Chromium native messaging host name | the installed extension calls it by name |
| Hook paths in `.claude/settings.json` | install paths of the optional agent kit, written by its adopt step |
| Three recorded commands in `consolelabs-urls.md` and `dev-ready.md` | rewriting them would falsify the record |

Outside the tree and unchangeable here: git history, and the Apple team's legal name that `codesign` shows and the App Store lists as seller.

## Reproduce

The commands above, from the repo root. The tests need the VM or a Mac with the CONTRIBUTING.md tools; the dry runs need nothing but the keychain.
