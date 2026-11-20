# Docs index

The root [README.md](../README.md) is the user guide: install, use, the CLI, the MCP server. A coding agent needs only [AGENTS.md](../AGENTS.md) at the repo root; it reads the pages here on demand. This page lists every doc by who reads it.

## Layout

| Folder | Who reads it | What is in it |
|---|---|---|
| [dev/](dev/) | Contributors and agents | How to build, test and release |
| [decisions/](decisions/) | Maintainers and contributors | Decision records (ADRs): what was decided, why, and what was ruled out. Numbered, one per decision |
| [implementation-notes/](implementation-notes/) | Maintainers | Per-change notes: only what differed from the brief |
| [verification/](verification/) | Anyone tracing a change | Proof files, one per PR. Dated records: add, never rewrite |
| [implementation-notes/](implementation-notes/) | Maintainers and contributors | Per change: the decisions the brief did not make, tradeoffs, open questions |
| [images/](images/) | The README | Screenshots |
| [app-store/](app-store/) | Maintainers | The App Store listing data and screenshots |

A new how-to page goes in `dev/`. Add it to this index in the same PR.

## Users

| Doc | What it covers |
|---|---|
| [../README.md](../README.md) | Download, features, the CLI, the MCP server, `spacedown docx`, building the app from source |
| [PRIVACY.md](PRIVACY.md) | The privacy policy: Spacedown collects no data, and what each part loads |
| [../NOTICE](../NOTICE) | The license: AGPL-3.0-only after v1.1.0, which versions stay MIT, and the license of contributions |
| [../TRADEMARKS.md](../TRADEMARKS.md) | The Spacedown name and icon: what you can do with them, and when a build needs a different name |
| [../CHANGELOG.md](../CHANGELOG.md) | What changed in each release, users first, developers last |
| [../SECURITY.md](../SECURITY.md) | How to report a vulnerability privately, which versions get fixes, what to expect |
| [../integrations/README.md](../integrations/README.md) | The Finder "Open With" app and the Chromium drop extension |

## Contributors

| Doc | What it covers |
|---|---|
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Prerequisites, a fresh clone to green tests, code style, commits, PRs, issues |
| [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | The Contributor Covenant 2.1 and how to report a conduct problem |
| [../AGENTS.md](../AGENTS.md) | The rules every change follows: size the work, branch and PR, proof of done, when to stop and ask |
| [dev/development.md](dev/development.md) | How the parts fit, build commands, project layout, vendored code |
| [dev/testing.md](dev/testing.md) | Test tiers, what CI runs and what stays local, skips, bash 3.2, known failures |
| [decisions/0001-agpl-and-paid-feature-gate.md](decisions/0001-agpl-and-paid-feature-gate.md) | ADR 0001: AGPL, the one paid-feature gate, the offline Ed25519 license file, the license ask |
| [contract-r1.md](contract-r1.md) | The release 1 contract: the render core's hooks and settings, which files are frozen, which part owns which section |
| [verification/README.md](verification/README.md) | How to write a proof file |
| [../assets/REFRESH.md](../assets/REFRESH.md) | Where the vendored stylesheet and highlight.js come from and how to refresh them |
| [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) | Licenses of bundled third-party code and fonts |

## Maintainers

| Doc | What it covers |
|---|---|
| [dev/release.md](dev/release.md) | The release flow, what it needs by role, the store scripts, what to do when it stops |
| [app-store/metadata.json](app-store/metadata.json) | The App Store listing text `scripts/asc_listing.py` uploads |

## Elsewhere in the repo

| File | What it is |
|---|---|
| `../.github/workflows/ci.yml` | CI: the owner check, tests, the app build, the workflow lint, and the `CI summary` check a merge needs |
| `../.github/workflows/pr-shape.yml` | The `PR shape` check on every PR: title, proof, issue link ([dev/testing.md](dev/testing.md#merge-checks)) |
| `../.github/CODEOWNERS` | Who owns what; every script and workflow has its own line (`scripts/check-owners.sh`) |
| `../.github/pull_request_template.md` | The PR body: What, Demo, Proof, Notes |
| `../.github/dependabot.yml` | Weekly, grouped updates for the GitHub Actions the workflows use |
| `../.github/ISSUE_TEMPLATE/` | The bug report and the feature or task forms |
| `../tests/known-failures.txt` | Checks that are red on purpose, with the reason; empty means all must pass |
| `../.kit.toml` | Settings for the optional agent kit |
