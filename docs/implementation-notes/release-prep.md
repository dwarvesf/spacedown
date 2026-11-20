# release-prep: implementation notes

Only what differs from, or adds to, the maintainer's brief for this PR (release notes from CHANGELOG, keep older releases by default, the version bump).

- **Version 1.2.0.** The Unreleased section adds features (X-ray, Present, the reading modes, `spacedown mcp`, Intel support), so it is a minor bump. `MARKETING_VERSION` in `project.yml` and the Xcode project moved in the contract PR (#100): both files are frozen, and the agent guard keeps frozen files on `contract/` branches. This PR bumps the rest: `bin/spacedown`, both extension manifests and `scripts/asc_listing.py`.
- **CHANGELOG.** Before moving Unreleased under `## [1.2.0] - 2026-11-21`, this PR adds lines for the merged PRs that had none (#88, #89, #94, #95, #98, #99) and for this batch (#100 and this PR). An empty `## [Unreleased]` stays on top. The `[1.2.0]` link compares v1.1.0 to v1.2.0, so it works once the tag exists.
- **Notes check before the build.** `release.sh` reads the notes right after the version check and stops on a missing or empty section, so a release cannot reach notarization with no notes. A dry run prints the notes and the keep or prune decision there, before any check that needs a credential.
- **`KEEP_OLD_RELEASES` is gone.** Keeping is the default, so the variable has nothing left to do; `PRUNE_OLD_RELEASES=1` opts in to the old behavior.
- **`tests/release-notes-test.sh`** is new, owned in CODEOWNERS and run by CI's unit test step. It also checks that the CHANGELOG has a section for the version in `project.yml`, so a version bump without notes fails CI instead of the release.
- **CONTRIBUTING** gets the `contract/<slug>` branch type.
