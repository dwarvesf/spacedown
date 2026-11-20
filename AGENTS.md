<!-- kit:agents-pointer v1 -->
# AGENTS.md

This file is the repo's instruction file for coding agents and people. `CLAUDE.md` only imports it.

Everything you need is in this file and the files it names. No plugin or extra tool is required: a shell with `git` and `gh`, plus the tools in [CONTRIBUTING.md](CONTRIBUTING.md#prerequisites), is enough.

## What this repo is

Spacedown is a macOS Quick Look extension that renders Markdown, plus a `spacedown` CLI and a stdio MCP server that use the same JavaScript render core.

```
 bin/spacedown (bash CLI) ──┐
                            ├──► render core (JS: marked, KaTeX, highlight.js)
 Spacedown.app              │      integrations/safari/quick-look/Resources/
   └─ SpacedownQL.appex ────┘      run by osascript (CLI) or JavaScriptCore (Quick Look)
 spacedown mcp (stdio) ──► the CLI ──► the render core
```

## Commands

Run each command from the repo root.

| Area | Run | When |
|---|---|---|
| Every check below | `bash scripts/check.sh` (`--quick` skips the smoke suite while you iterate) | before every push; exit 0 is the bar |
| Smoke suite | `bash tests/smoke.sh` (`--list` names the sections, `--only cli,docx` runs some) | every change; CI runs it |
| Unit tests outside smoke | `bash tests/katex-one-test.sh`, `bash tests/size-budget-test.sh`, `node tests/hljs-bundle-test.js` | KaTeX, size budget or highlight.js changes; CI runs them |
| One render test | `node integrations/safari/quick-look/test-render.js` (also `test-contract.js`, `test-boxdraw.js`, `test-xray.js`, `test-present.js`) | while you iterate on the render core |
| App build | `NO_INSTALL=1 integrations/build-safari.sh` (`--with-safari` adds the Safari extension and helper) | Swift, Xcode project or Quick Look resource changes; CI runs it |
| Install and look | `integrations/build-safari.sh`, then press space on a `.md` file in Finder | any change to what the Quick Look panel shows; never in CI, and never on a daily-use Mac: use a macOS VM or a clean macOS user ([`ui-change`](.claude/skills/ui-change/SKILL.md)) |
| Workflow lint | `actionlint` | `.github/workflows/` changes; CI runs it |

- `integrations/build-safari.sh` without `NO_INSTALL=1` installs the app into `~/Applications`, registers the extension and opens the app. Use `NO_INSTALL=1` unless you mean to install.
- `scripts/check.sh` runs the syntax check, the smoke suite under `/bin/bash`, the unit tests, the agent harness tests and `actionlint` when installed. It does not build the app or open the panel; the table above says when you do.
- What CI runs and what stays local: [docs/dev/testing.md](docs/dev/testing.md).
- Branches, commits and code style: [CONTRIBUTING.md](CONTRIBUTING.md). How the parts fit: [docs/dev/development.md](docs/dev/development.md).

## Rules for agents and contributors

### Size the work
- Tiny: a typo, a comment, a doc line. Normal: one feature or fix. Full: anything that touches the release contract, signing, entitlements, the sandbox, the Quick Look extension's data access, the MCP interface, or the release scripts.
- A full change states its plan in the PR body before the code, and gets a maintainer's yes before merge.

### Branch and PR
- Work on a branch named `<type>/<short-slug>` and open a PR against `main`. Never push to `main` and never commit on it.
- The PR title is a conventional commit (`type(scope): subject`, 72 characters or less): a squash merge makes it the commit subject on `main`.
- The PR body follows [.github/pull_request_template.md](.github/pull_request_template.md).
- CI must be green before merge.

### Proof of done
- A change to behavior (any changed file that is not documentation) adds `docs/verification/<slug>.md`, one file per PR.
- The file holds `Command:` / `Exit:` / `Output:` / `Verdict:` blocks with the real, trimmed output, and a negative control: break the change on purpose, show the test go red, restore. How to write one: [docs/verification/README.md](docs/verification/README.md).
- A change to what the panel or a page shows also commits a screenshot under `docs/verification/<slug>/`. The live panel is checked in a macOS VM or a clean macOS user, never on a daily-use Mac.
- Proof files are dated records. Add to them; never rewrite an old one.
- A PR with no behavior change (documentation, or configuration no test can run, such as an issue template or an agent settings file) writes `no-proof: <reason>` on its own line in the PR body instead of a proof file. The reason is 10 or more characters and says why no behavior changes. The PR-shape CI job checks the marker. A behavior change with a `no-proof:` line is sent back in review.

### The release contract
- `docs/contract-r1.md` freezes some files and hooks. A change to a frozen file goes through its own contract PR first, never inside a feature PR. The contract PR is on a branch named `contract/<slug>`, changes only the frozen files, and says why in its body.
- The frozen files are listed in [scripts/agent-frozen-paths.txt](scripts/agent-frozen-paths.txt). The agent hook refuses an edit or a commit that touches one on any other branch, and `scripts/test-agent-guard.sh` fails when that list and the contract disagree.
- A check that is red on purpose is listed in `tests/known-failures.txt`. An empty list means every check on `main` must pass.

### Stop and ask a maintainer before you
- change an interface: the CLI flags, the MCP tools, the render core's hooks, or a file `docs/contract-r1.md` freezes;
- choose which of two files is canonical, or move a file other tools read;
- weaken, skip or delete a test, a check or a CI job;
- touch signing, notarization, entitlements, bundle ids, the release scripts, or anything that needs a secret or account access;
- add a runtime dependency or a network call (the app and CLI run offline by design).

### One-way doors
A door is hard to undo once it ships. A change that touches one needs a maintainer's decision before you edit it. Name the door in the PR Notes and link the maintainer's yes. A reversible change merges on green checks and review; unsure whether it is a door? Treat it as one.

| Door | Paths or change | Why it is one way | Held by |
|---|---|---|---|
| Contract-frozen files | the list in [scripts/agent-frozen-paths.txt](scripts/agent-frozen-paths.txt), from `docs/contract-r1.md` | other code and the settings store are built against them | agent hook (a `contract/<slug>` branch), review |
| Release and signing | `scripts/release.sh`, `scripts/mas-altool.sh`, `scripts/asc_setup.py`, `scripts/asc_listing.py`, `docs/dev/release.md`, `*.entitlements`, notarization and provisioning material | a release publishes and deletes the older ones; a signing change breaks update paths | review; never run a release script |
| Bundle ids and the App Group | `dfoundation.spacedown`, `dfoundation.spacedown.quicklook`, the App Group id in `docs/contract-r1.md`, `Info.plist`, `project.yml`, `project.pbxproj` | stored settings, store listings and installed copies are keyed to them | review (most of these paths are frozen files too) |
| License and trademark | `LICENSE`, `NOTICE`, `TRADEMARKS.md`, the license of contributions in `CONTRIBUTING.md` and the PR template | versions already released keep the license they shipped under | review |
| CI workflows | `.github/workflows/`, `.github/actionlint.yaml` | the repo is public: a workflow change can spend money or expose a secret; never a self-hosted runner | review |
| Public interfaces and the privacy promise | CLI flags, MCP tools, render core hooks, any network call, `docs/PRIVACY.md` | users script against them; the app and CLI run offline by design | review, "Stop and ask" above |
| The agent harness itself | `.claude/settings.json`, `scripts/agent-guard.sh`, `scripts/agent-frozen-paths.txt` | they decide what an agent may do without asking | review |

### Never
- Never commit secrets, signing material, provisioning profiles, or build output (`build/`, rendered `.html`).
- Never run `scripts/release.sh`: it publishes a release and deletes the older ones. Only a maintainer cuts a release ([docs/dev/release.md](docs/dev/release.md)).
- Never add a self-hosted runner to CI. The repo is public; a fork PR would run on that machine.
- Never use em or en dashes in code, comments or docs.

## Lessons

[.claude/memory/MEMORY.md](.claude/memory/MEMORY.md) lists what past work already paid for, one line each. Claude Code prints it at session start through the hook in `.claude/settings.json`. Other agents: run `bash scripts/agent-lessons.sh` or read the file. Read the note before you do the work it covers.

Add a lesson when your PR paid for one. One note per lesson, in the same PR: a file `.claude/memory/<slug>.md` with `name` and `description` in the frontmatter, then the fact, the why and how to apply it, under 1,200 characters, with no personal names and no dates. Add one line to `MEMORY.md`. Keep `MEMORY.md` under 10,000 characters: Claude Code shows only a 2,000 character preview of longer hook output. `bash scripts/agent-lessons.sh --verify` checks the index and `scripts/check.sh` runs it.

## Playbooks and hooks

- Playbooks (commands only; the rules stay here): [.claude/skills/ship-pr/SKILL.md](.claude/skills/ship-pr/SKILL.md) takes a change to a green PR, and [.claude/skills/ui-change/SKILL.md](.claude/skills/ui-change/SKILL.md) covers what the panel or a page shows.
- `.claude/settings.json` wires `scripts/agent-guard.sh` (Claude Code only; it needs `jq` and refuses every call without it). It refuses exactly these: a push to `main`, a force push or `--mirror`, `--no-verify` (and `git commit -n`), setting `core.hooksPath`, a commit while `main` is checked out, and an edit or commit of a contract-frozen file off a `contract/` branch. The guard, its list and `.claude/settings.json` count as frozen, and the list is read as committed on `origin/main`. Switch branches in one call and commit in the next: the guard sees the branch you are on now.
- Known gaps: the guard is a best-effort seatbelt against accidents, not a security boundary. It reads command text and judges only commands that start with `git`, so a determined agent can get past it: `bash -c` or `eval`, a script or variable that runs git, config includes (`include.path`, `includeIf`), `GIT_CONFIG_*` or `GIT_DIR` set in front of git or exported. The real control is the server-side ruleset on `main`: a required PR, required checks, no force push. [The lesson](.claude/memory/guards-match-command-text.md).
- The same file runs the optional kit's hooks through `scripts/agent-kit-hook.sh`, which does nothing when the kit is not installed.

## Where docs live

- [docs/README.md](docs/README.md) is the index, grouped by reader.
- `docs/dev/`: how to build, test and release. A new how-to page goes here.
- `docs/verification/`: proof files, one per PR. `docs/images/`: README screenshots. `docs/app-store/`: store listing data.
- Fix any doc your change makes wrong in the same PR, and add a new doc to the index.

## If the agent kit is installed (optional)

Nothing above needs it. Some maintainers run an agent kit whose gates read `.kit.toml` and `.claude/settings.json`. Every kit hook in that file goes through `scripts/agent-kit-hook.sh`, so a contributor without the kit sees no hook error. Where the kit's generic rules differ from the rules above, this file wins.
