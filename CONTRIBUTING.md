# Contributing

Thanks for helping. This page takes you from a fresh clone to a green test run, then covers the code style, commits, PRs and issues. The rules every change follows (proof of done, what needs a maintainer's yes) are in [AGENTS.md](AGENTS.md). How the parts fit: [docs/dev/development.md](docs/dev/development.md).

## Prerequisites

Spacedown builds and runs on macOS only: the CLI renders through `osascript` and the app is a Quick Look extension.

| Tool | Needed for | Check |
|---|---|---|
| macOS 13 or later | running the app (the app target's deployment target is 13.0) | `sw_vers -productVersion` |
| Xcode, with its command line tools | building the app (`xcodebuild`, `swiftc`). CI builds with the newest Xcode on the `macos-26` runner image | `xcodebuild -version` |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | generating the Quick Look project from `project.yml` (`brew install xcodegen`) | `xcodegen --version` |
| Node | the render core tests, the plug-in tests, the MCP test and the Skim parity check. The suite fails without it. CI uses Node 24 | `node --version` |
| Python 3 | the reading-mode checks and the `--watch` reload server (`/usr/bin/python3` is enough) | `python3 --version` |
| A Chromium-family browser: Google Chrome, Helium, Brave, Edge or Chromium | the headless checks (`--shot`, reading modes, KaTeX fonts). Without one they skip. `SPACEDOWN_TEST_BROWSER=<binary>` picks one | any of them in `/Applications` |
| pandoc | `spacedown docx` in the iA look. The test suite's `docx` section fails without it (`brew install pandoc`). Users of the CLI need it only for `docx` | `pandoc --version` |
| entr (optional) | the `--watch` check (`brew install entr`) | `command -v entr` |

The test suite skips a check when a browser, entr or python3 is missing, and says so with a `skip:` line. Without node or pandoc it fails. To run what CI runs, install all of them:

```bash
brew install xcodegen pandoc entr node
```

## From a fresh clone

```bash
git clone https://github.com/consolelabs/spacedown
cd spacedown

bash tests/smoke.sh                 # ends with "smoke: all N passed"
bash tests/katex-one-test.sh        # "katex-one-test: N passed, 0 failed"
bash tests/size-budget-test.sh      # "size-budget-test: N passed, 0 failed"
node tests/hljs-bundle-test.js      # "hljs-bundle-test: all passed"

NO_INSTALL=1 integrations/build-safari.sh   # builds and ad hoc signs the app, prints its path
```

`NO_INSTALL=1` stops after the build: nothing is installed or launched. Without it the script installs `Spacedown.app` into `~/Applications`, registers the Quick Look extension and opens the app once. Then select a `.md` file in Finder and press space. If no preview shows, turn Spacedown on under System Settings > General > Login Items & Extensions > Quick Look.

To use your checkout's CLI: `ln -sfn "$PWD/bin/spacedown" ~/.local/bin/spacedown`, then `spacedown tests/fixture/fixture.md`.

Test tiers, what CI runs and what stays local: [docs/dev/testing.md](docs/dev/testing.md).

## Code style

There is no formatter or linter for the shell, JavaScript or Swift code. Match the file you edit.

- Bash scripts start with `set -euo pipefail` (tests use `set -uo pipefail` so one failure does not stop the run) and keep their usage in the header comment.
- The render core in `integrations/safari/quick-look/Resources/` runs in two places: JavaScriptCore inside the Quick Look extension and `osascript` for the CLI. No DOM, no network, no Node modules in it.
- The app and the CLI work offline. Do not add a network call or a runtime dependency without a maintainer's yes.
- A comment says why: the constraint or failure behind the line. Do not restate the code. Code never names an issue, a PR or a ticket.
- Vendored code (KaTeX, marked, highlight.js, the iA fonts, the VS Code stylesheet) keeps its notice in `THIRD_PARTY_NOTICES.md`. `assets/REFRESH.md` says how to refresh it.
- No em or en dashes anywhere. Use a comma, a colon, a semicolon or parentheses.

## Commits and branches

- Branch names: `<type>/<short-slug>`, type `feat`, `fix`, `refactor`, `docs`, `test`, `chore` or `ci`, two to five kebab-case words.
- Conventional commits: `type(scope): subject`, 72 characters or less, one logical change per commit.
- Do not switch branches in a checkout that someone else (or another agent) is using: use `git worktree add`.
- Never stage `build/`, rendered `.html` files, `.DS_Store`, signing material or secrets.

## Pull requests

1. Fork the repo (or branch, if you have write access) and open a PR against `main`.
2. Fill in [the PR template](.github/pull_request_template.md): what changed, a demo, the proof file.
3. A behavior change adds `docs/verification/<slug>.md` with a green run and a negative control ([how](docs/verification/README.md)). A change to what the panel shows adds a before and after screenshot.
4. Fix any doc your change makes wrong in the same PR.
5. CI runs on every PR that changes more than docs. It must be green before a maintainer merges. A first-time contributor's run waits for a maintainer to approve it.

The PR title becomes the commit subject on `main` (squash merge), so write it as a conventional commit.

## Issues

- Bug: use the **Bug report** form. Include your macOS version, the Spacedown version (`spacedown --version` or the app's About box), how you installed it, and a small Markdown file that shows the problem.
- Feature or task: use the **Feature or task** form. Say what should be true when it is done, and one check that shows it.
- Security problem: never put the details in a public issue. Open an issue titled "Security contact" with no details, and a maintainer will reply with a private channel.

## Releases

Only a maintainer cuts a release. The flow and what it needs: [docs/dev/release.md](docs/dev/release.md).
