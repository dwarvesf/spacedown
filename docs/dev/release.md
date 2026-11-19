# Releasing

Only a maintainer cuts a release, by hand on a Mac. Nothing in CI signs, notarizes or publishes. Contributors never run `scripts/release.sh`: it publishes a GitHub release and deletes the older ones.

```
 bump versions ──► PR, merge ──► scripts/release.sh on a clean main
                                   │
                                   ├─ build (Quick Look only) + Developer ID signature
                                   ├─ size budget check
                                   ├─ notarize + staple the app, Gatekeeper check
                                   ├─ zip + dmg, notarize the dmg, Gatekeeper check
                                   ├─ GitHub release vX.Y.Z with both files and the sha256
                                   └─ delete older releases and tags (KEEP_OLD_RELEASES=1 keeps them)
                                 ──► bump the Homebrew cask
                                 ──► Mac App Store build (scripts/release.sh --mas), separate
```

## Versioning

The version is `MAJOR.MINOR.PATCH`. One version lives in several files. Bump all of them. `release.sh` reads the version from `project.yml` and refuses to run until `bin/spacedown` and both extension manifests match it; it does not check the Xcode project, so check that one by eye.

| File | Field |
|---|---|
| `integrations/safari/quick-look/project.yml` | `MARKETING_VERSION` (the default version `release.sh` reads) |
| the Xcode project of the container app | `MARKETING_VERSION` |
| `bin/spacedown` | `VERSION` |
| `integrations/extension/manifest.json` and the Safari extension's `manifest.json` | `version` |

The Releases page carries one release: each new version replaces the previous one.

## Steps

1. Bump the version in every file above in one PR. Merge it.
2. On a clean `main`, run `scripts/release.sh --dry-run` first: it runs every precondition check, prints the identity and notary credentials it would use, and stops before the build. Then run `scripts/release.sh`. It checks the same preconditions and stops on the first one that fails.
3. Bump `Casks/spacedown.rb` in [consolelabs/homebrew-tap](https://github.com/consolelabs/homebrew-tap) to the new version and the zip's sha256 (the release notes carry it).
4. Mac App Store: `scripts/release.sh --mas` builds the signed store package. Upload it to App Store Connect, attach the build to a new version, and submit it for review.

## What a release needs, by role

The values live with the maintainers, never in this repo. The script header lists every setting and its default.

| Need | Used by | Who holds it |
|---|---|---|
| A Developer ID Application signing identity in the login keychain. `release.sh` finds it by `TEAM_ID`; `SIGN_ID` overrides | the direct download (`release.sh`) | the Apple developer account holder |
| Notary credentials: a `notarytool` keychain profile named by `NOTARY_PROFILE` (no default), or an App Store Connect API key (`NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`) | notarizing the app and the dmg | the Apple developer account holder |
| `gh` signed in with write access to this repo | publishing the GitHub release | a maintainer |
| Apple Distribution and Mac Installer Distribution identities, and the Mac App Store provisioning profiles (`PROFILE_DIR`) | `release.sh --mas` | the Apple developer account holder |
| An App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID` and the key file for `UPLOAD=1`; for the three store scripts, a password manager item named by `OP_VAULT` and `ASC_OP_ITEM`. `asc_setup.py` also needs `MAS_P12_OP_TITLE` and `CSR_SUBJECT`, `asc_listing.py` needs `REVIEW_CONTACT_BUNDLE`. None has a default; each script names the one that is missing | `UPLOAD=1`, `scripts/mas-altool.sh`, `scripts/asc_setup.py`, `scripts/asc_listing.py` | the App Store Connect admin |
| Push access to the Homebrew tap | the cask bump | a tap maintainer |

Useful switches: `--dry-run` checks and stops, `DRAFT=1` makes a draft release, `PUBLISH=0` stops after the notarized zip with no GitHub release, `KEEP_OLD_RELEASES=1` keeps the older releases.

## Store listing and screenshots

These are separate scripts, not called by `release.sh`. Each of `asc_setup.py`, `asc_listing.py` and `mas-altool.sh` takes `--dry-run` as its first argument: it checks its arguments and settings and stops before reading a secret or calling Apple.

| Script | What it does |
|---|---|
| `scripts/asc_setup.py` | One-time App Store Connect setup: registers the bundle ids, creates the distribution certificates and saves the provisioning profiles |
| `scripts/asc_listing.py` | Fills the App Store Connect listing through the API from `docs/app-store/metadata.json` and screenshot PNGs. Never submits for review |
| `scripts/mas-altool.sh validate\|upload <pkg>` | Validates or uploads the signed store package with `altool` |
| `scripts/store-shots.sh` | Renders the two App Store screenshots from the real Quick Look preview through headless Brave (`scripts/launch.md` light, `scripts/showcase.md` dark) |
| `scripts/readme-shots.sh` | Renders the test fixture through the Quick Look pipeline and screenshots it into `docs/images/` |
| `scripts/window-shots.sh` | Screenshots the app window page, light and dark, at the sizes the app sets |
| `scripts/qlwrap.js` | Wraps a Quick Look render body the way the extension does; used by the two shot scripts |

## If it stops

`release.sh` prints `release: <reason>` and exits 1. The common ones:

| Message | Fix |
|---|---|
| `version X not set in: ...` | bump the listed files and merge |
| `dirty tree; commit first` | commit or stash, run again |
| `signing identity missing` | install the identity in the login keychain |
| `no notary credentials` or `notary credentials rejected` | set `NOTARY_PROFILE` to a profile stored with `xcrun notarytool store-credentials <name>`, or set the API key variables |
| `no Developer ID Application identity for team ...` | install the identity in the login keychain, or set `SIGN_ID` |
| `... over its size budget` | see `scripts/size-budget`; the budget is a check, not a target to raise casually |
| `release vX already exists` | the tag is taken: bump the version |
