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
| Smoke suite | `bash tests/smoke.sh` (`--list` names the sections, `--only cli,docx` runs some) | every change; CI runs it |
| Unit tests outside smoke | `bash tests/katex-one-test.sh`, `bash tests/size-budget-test.sh`, `node tests/hljs-bundle-test.js` | KaTeX, size budget or highlight.js changes; CI runs them |
| One render test | `node integrations/safari/quick-look/test-render.js` (also `test-contract.js`, `test-boxdraw.js`, `test-xray.js`, `test-present.js`) | while you iterate on the render core |
| App build | `NO_INSTALL=1 integrations/build-safari.sh` (`--with-safari` adds the Safari extension and helper) | Swift, Xcode project or Quick Look resource changes; CI runs it |
| Install and look | `integrations/build-safari.sh`, then press space on a `.md` file in Finder | any change to what the Quick Look panel shows; never in CI |
| Workflow lint | `actionlint` | `.github/workflows/` changes; CI runs it |

- `integrations/build-safari.sh` without `NO_INSTALL=1` installs the app into `~/Applications`, registers the extension and opens the app. Use `NO_INSTALL=1` unless you mean to install.
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
- A change to what the panel or a page shows also commits a screenshot under `docs/verification/<slug>/`.
- Proof files are dated records. Add to them; never rewrite an old one.

### The release contract
- `docs/contract-r1.md` freezes some files and hooks. A change to a frozen file goes through its own contract PR first, never inside a feature PR.
- A check that is red on purpose is listed in `tests/known-failures.txt`. An empty list means every check on `main` must pass.

### Stop and ask a maintainer before you
- change an interface: the CLI flags, the MCP tools, the render core's hooks, or a file `docs/contract-r1.md` freezes;
- choose which of two files is canonical, or move a file other tools read;
- weaken, skip or delete a test, a check or a CI job;
- touch signing, notarization, entitlements, bundle ids, the release scripts, or anything that needs a secret or account access;
- add a runtime dependency or a network call (the app and CLI run offline by design).

### Never
- Never commit secrets, signing material, provisioning profiles, or build output (`build/`, rendered `.html`).
- Never run `scripts/release.sh`: it publishes a release and deletes the older ones. Only a maintainer cuts a release ([docs/dev/release.md](docs/dev/release.md)).
- Never add a self-hosted runner to CI. The repo is public; a fork PR would run on that machine.
- Never use em or en dashes in code, comments or docs.

## Where docs live

- [docs/README.md](docs/README.md) is the index, grouped by reader.
- `docs/dev/`: how to build, test and release. A new how-to page goes here.
- `docs/verification/`: proof files, one per PR. `docs/images/`: README screenshots. `docs/app-store/`: store listing data.
- Fix any doc your change makes wrong in the same PR, and add a new doc to the index.

## If dwarves-kit is installed (optional)

Nothing above needs it. Its contract lives at `~/.claude/dwarves-kit/AGENTS.md` and https://github.com/dwarvesf/dwarves-kit/blob/master/AGENTS.md, and its gates read `.kit.toml`. Where the kit's generic rules differ from the rules above, this file wins.
