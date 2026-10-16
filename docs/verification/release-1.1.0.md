# Proof of Done, release 1.1.0

Version bump to 1.1.0 for the ia/tm modes, spacedown-docx, embedded iA fonts and local images, the reading-view polish and the iA table fix. `scripts/release.sh` gains App Store Connect API key notarization (`NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`), so a release runs on a host without the `DWARVES_NOTARY` keychain profile; every notarytool call goes through one auth array.

**Date:** 2026-10-16 · **Lane:** normal · **Host:** Mac-mini-2 · **Branch:** `chore/release-1.1.0`

## Green run

```
Command: bash tests/smoke.sh && bin/spacedown --version && bash -n scripts/release.sh
Exit: 0
Output:
smoke: all 68 passed
spacedown 1.1.0
(release.sh syntax ok; 4 notarytool calls use "${NOTARY_AUTH[@]}")
Verdict: PASS
```

The release run itself (build, notarize, staple, zip and dmg, GitHub release) is the live proof; its result is recorded on the GitHub release v1.1.0.

## Rollback

Revert this squash commit; release.sh goes back to the keychain profile only and the version strings to 1.0.3.
