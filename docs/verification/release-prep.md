# Proof of Done, release-prep

Release notes come from CHANGELOG.md (`scripts/release-notes.sh`), `scripts/release.sh` keeps older releases and tags unless `PRUNE_OLD_RELEASES=1`, and the version is 1.2.0 everywhere (`project.yml` and the Xcode project moved in #100). Only dry runs: nothing was built, signed, notarized, tagged or published.

## Green run

```
Command: bash tests/release-notes-test.sh   (under /bin/bash)
Exit: 0
Output:
  ok   the section body alone, from its first line to its last
  ok   a middle section stops at the next heading
  ok   an empty last section fails (link references are not notes)
  ok   a missing version fails and says so
  ok   a malformed version is a usage error
  ok   CHANGELOG.md has notes for 1.2.0 (project.yml)
  ok   release.sh publishes the CHANGELOG notes, no fixed string
release-notes-test: 7 passed, 0 failed
Verdict: PASS
```

```
Command: scripts/release.sh --dry-run   (clean tree on this branch, rebased on #100; no notary credentials set)
Exit: 1 (stops at the notary check, after the notes)
Output:
  dry run: release notes for v1.2.0 (from CHANGELOG.md), then the zip's sha256:
    | ### Added
    |
    | - Spacedown runs on Intel Macs too: the app and its Quick Look extension are universal (arm64 and x86_64) (#100).
    | - Writing X-ray lens in the Quick Look panel (#68).
    | ...                                   (the whole 1.2.0 section, 56 lines, down to its last entry)
    | - Removed the pandoc-era filters and unused KaTeX copies, and dropped the pandoc-for-HTML claims from the docs (#73, #75).
  dry run: older releases and their tags are kept (PRUNE_OLD_RELEASES=1 deletes them)
  release: no notary credentials: set NOTARY_PROFILE to a notarytool keychain profile (xcrun notarytool store-credentials <name>), or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER
Verdict: PASS: the notes and the keep decision print before any check that needs a credential
```

```
Command: PRUNE_OLD_RELEASES=1 scripts/release.sh --dry-run
Exit: 1 (same notary stop)
Output:
  dry run: older releases and their tags would be DELETED (PRUNE_OLD_RELEASES=1)
Verdict: PASS: pruning only on request
```

The version check passes: `release.sh` reads 1.2.0 from `project.yml` and finds it in `bin/spacedown` and both manifests (it would print `version 1.2.0 not set in: ...` otherwise). The notary stop is expected on a contributor machine; the notary credentials were not fetched for this proof.

Also run: `bash tests/smoke.sh --only cli` (36 passed), `bash scripts/check-owners.sh` (45 owned).

## Negative control

```
Command: tests/release-notes-test.sh against main's release.sh (before this change)
Exit: 1
Output:
  FAIL release.sh does not use release-notes.sh
release-notes-test: 6 passed, 1 failed
Verdict: RED as expected: the fixed-string notes are caught

Command: CHANGELOG heading renamed to "## [1.2.0-draft]", then scripts/release.sh --dry-run and tests/release-notes-test.sh; restored with git checkout
Exit: 1 and 1
Output:
  release: no release notes for 1.2.0: add a "## [1.2.0]" section to CHANGELOG.md
  FAIL CHANGELOG.md has no notes for 1.2.0
  release-notes-test: 6 passed, 1 failed
Verdict: RED as expected: a version without notes stops the release before the build, and fails CI first
```

## Not proven

- No real release ran. `gh release create` with the multi-line notes and the prune loop were not executed; the prune loop is the old one behind the new switch.
- `scripts/release.sh --mas` is unchanged and was not run.

## Rollback

Revert the squash commit: fixed-string notes, older releases deleted by default, version strings back to 1.1.0 outside the two project files.
