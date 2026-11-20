# Testing

Every test runs from the repo root on macOS. Setup and prerequisites: [CONTRIBUTING.md](../../CONTRIBUTING.md#prerequisites).

## Tiers

| Tier | Command | What it covers | CI |
|---|---|---|---|
| Smoke suite | `bash tests/smoke.sh` | The CLI contract, the reading chrome, themes, fonts, `spacedown docx`, reading modes, the Skim parity check, the app bundle wiring, `--shot`, KaTeX, the plug-ins and the MCP server. It also runs the Quick Look render tests | yes |
| KaTeX | `bash tests/katex-one-test.sh [<built Spacedown.app>]` | One pinned KaTeX for script, stylesheet and fonts; the panel page and the CLI page both typeset the math fixture with every font loaded | yes (without an app) |
| Size budget | `bash tests/size-budget-test.sh` | `scripts/size-budget` passes a small app and fails an oversized one | yes |
| highlight.js | `node tests/hljs-bundle-test.js` | The custom highlight.js build knows every language the preview promises and stays small | yes |
| Render core | `node integrations/safari/quick-look/test-render.js` (and `test-contract.js`, `test-boxdraw.js`, `test-xray.js`, `test-present.js`) | One part of the render core, fast; the smoke suite runs all of them | through smoke |
| App build | `NO_INSTALL=1 integrations/build-safari.sh --with-safari` | The app, both extensions and the render helper compile and sign ad hoc | yes |
| Workflow lint | `actionlint` | `.github/workflows/` | yes |
| Owners | `bash scripts/check-owners.sh` | Every script and workflow has its own line in `.github/CODEOWNERS` | yes |
| PR shape | `bash scripts/pr-shape-test.sh`; one PR by hand: `PR_TITLE=... PR_BODY=... BASE_SHA=... HEAD_SHA=... bash scripts/pr-shape.sh` | The PR title, the proof file or `no-proof:` line, the issue link | yes, on every PR |
| Live panel | `integrations/build-safari.sh`, then press space on a `.md` file in Finder | What the real Quick Look panel shows | no: local only |

`bash tests/smoke.sh` ends with `smoke: all N passed` and exit 0. A failure prints `FAIL:` lines, then `smoke: N passed, M FAILED`, and exit 1.

## Running part of the suite

```bash
bash tests/smoke.sh --list            # the section names: cli, chrome, quicklook, render, docx, reading, mcp, ...
bash tests/smoke.sh --only docx,mcp   # just those sections; an unknown name exits 64
spacedown tests/fixture/fixture.md    # a synthetic document that exercises every feature, to look at by eye
```

## What skips, and why

A section skips (with a `skip:` line, not a failure) when its tool is missing:

| Missing | Skipped |
|---|---|
| node | the render core suites, the Skim parity check and the MCP session (but see below) |
| a Chromium-family browser | the headless checks: reading-mode behavior, `--shot`, the KaTeX font load. `SPACEDOWN_TEST_BROWSER=<binary>` picks one |
| entr or python3 | the `--watch` check |

Two tools fail instead of skipping. Without pandoc the `docx` section fails, because the iA-look `.docx` needs pandoc. Without node the box-drawing, X-ray and Present plug-in checks fail. Install both.

CI installs all of them, so nothing skips there. Check your own run for `skip:` lines before you call it green.

## bash 3.2

macOS ships bash 3.2 as `/bin/bash`, and CI runs the suite with it. Write test and build scripts that run under 3.2: no associative arrays, no `mapfile`, no `${var,,}`, and no heredoc inside `$( )` (3.2 misparses it; write the heredoc to a temp file first). CI runs `/bin/bash -n` on every `tests/*.sh`.

## Merge checks

Two checks gate a merge into `main`:

| Check | Workflow | Runs | Passes when |
|---|---|---|---|
| `PR shape` | `.github/workflows/pr-shape.yml` | every PR, again when the title or body is edited | the title is `type(scope): subject` (72 characters or less), the PR adds a proof file with a negative control or its body has a `no-proof: <reason>` line, and any `Closes #<n>` names a real number |
| `CI summary` | `.github/workflows/ci.yml` | every PR and every push to `main` | the owner check passed and every CI job passed or was skipped |

A docs-only change (`docs/`, `site/`, `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `LICENSE`, the issue and PR templates) skips the test and build jobs, and `CI summary` still reports. `README.md` is not docs-only here: the MCP test reads it.

`PR shape` runs the script from the base branch, so a PR cannot change the rules it is judged by. A change to `scripts/pr-shape.sh` takes effect for the PRs after it merges.

## Known failures

`tests/known-failures.txt` lists checks that are red on purpose while release work is in flight, one line each with the reason and until when. An empty list means every check on `main` must pass. Adding a line needs a maintainer's yes ([AGENTS.md](../../AGENTS.md)).

## What stays local

These need a GUI session, an installed app, signing identities or a specific browser, so CI does not run them:

| Check | Command | Needs |
|---|---|---|
| The real Quick Look panel | `integrations/build-safari.sh`, then `qlmanage -r; qlmanage -r cache; qlmanage -p <file.md>` | an installed app, a desktop session |
| The Safari drop extension | `integrations/build-safari.sh --with-safari`, then the steps in the README | Safari, "Allow unsigned extensions" |
| Layout at 390, 768, 1470 and 1728 px: overflow, edges, side gaps; exits 1 when a width scrolls sideways | `scripts/layout-check <file.md>` | Helium (`BROWSER` overrides) |
| README and store screenshots | `scripts/readme-shots.sh`, `scripts/store-shots.sh`, `scripts/window-shots.sh` | Brave Browser |
| A signed, notarized build | `scripts/release.sh` | maintainer only ([release.md](release.md)) |

A change to what the panel shows is checked live and gets a screenshot in its proof file.
