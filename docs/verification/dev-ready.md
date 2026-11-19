# Proof of Done, dev-ready

The repo gets what an outside developer needs: a self-contained `AGENTS.md`, `CONTRIBUTING.md`, a docs index with development, testing and release pages, issue and PR templates, and CI on GitHub-hosted macOS runners (the repo is public, so fork PRs never reach our hardware).

The first hosted CI run found a real bug: under macOS `/bin/bash` (3.2), `tests/smoke.sh` stopped at a parse error in section 39c and still exited 0, after 60 of its 192 checks. A stock Mac reported green on a third of the suite. The fix writes that heredoc to a temp file instead of inside `$( )`. CI now runs the suite with `/bin/bash`, parse-checks every `tests/*.sh` with it, and requires the summary line that only a complete run prints.

## Green run: hosted CI

Run: https://github.com/consolelabs/spacedown/actions/runs/44518159959 (head 50119ae, image `macos-26-arm64`, macOS 26.7.2, Node 24, Python 3.15, pandoc 3.13, Xcode 26.6 for the build)

```
Command: CI job "Tests (smoke suite and unit tests)"
Exit: 0
Output:
smoke: all 192 passed
katex-one-test: 9 passed, 0 failed
size-budget-test: 5 passed, 0 failed
hljs-bundle-test: all passed
(no skip: lines)
Verdict: PASS
```

```
Command: CI job "Build the app (unsigned, not installed)": NO_INSTALL=1 integrations/build-safari.sh --with-safari
Exit: 0
Output: build-safari: bundled the spacedown CLI into Contents/Resources/cli, then the signed app path
Verdict: PASS
```

```
Command: CI job "Lint workflows": actionlint 1.7.12
Exit: 0
Output: (no findings)
Verdict: PASS
```

## Green run: fresh clone, following CONTRIBUTING.md only

`git clone -b feat/dev-ready https://github.com/consolelabs/spacedown` into an empty scratch folder, at 50119ae. The tests ran in a clean macOS 27.2.1 VM (Xcode 27.2, Node 26, Python 3.9, pandoc 3.14, entr, Google Chrome); the build ran on the host with `NO_INSTALL=1`.

```
Command: bash tests/smoke.sh; bash tests/katex-one-test.sh; bash tests/size-budget-test.sh; node tests/hljs-bundle-test.js
Exit: 0
Output:
smoke: all 192 passed
katex-one-test: 9 passed, 0 failed
size-budget-test: 5 passed, 0 failed
hljs-bundle-test: all passed
Verdict: PASS
```

```
Command: /bin/bash tests/smoke.sh   (stock bash 3.2, as a fresh Mac runs it)
Exit: 0
Output: smoke: all 192 passed
Verdict: PASS
```

```
Command: NO_INSTALL=1 integrations/build-safari.sh
Exit: 0
Output: <scratch>/spacedown/integrations/safari/SpacedownDrop/build/Build/Products/Release/Spacedown.app
        (nothing written to ~/Applications)
Verdict: PASS
```

```
Command: bash ~/.claude/dwarves-kit/lib/adopt.sh --refresh --dry-run <worktree>
Exit: 0
Output:
adopt: agents-only mode on (adopt.agents_only knob): CLAUDE.md is left alone
adopt: AGENTS.md differs from the pointer by 83 lines (left alone)
Verdict: PASS (the optional kit does not overwrite the self-contained AGENTS.md)
```

## Negative control: the false green

The same VM, stock `/bin/bash`, `main`'s `tests/smoke.sh` against this branch's:

```
Command: /bin/bash tests/<v>.sh, then grep -Eq '^smoke: all [0-9]+ passed$' on its output (the CI guard)
Mutation: <v> = smoke-main, the file from origin/main
Exit: 0 (script), 1 (guard)
Output: smoke-main: script exit=0, ok lines=60, summary guard exit=1, last line: tests/smoke-main.sh: line 1983: syntax error near unexpected token `;;'
Restore: <v> = smoke, this branch
Exit: 0 (script), 0 (guard)
Output: smoke: script exit=0, ok lines=192, summary guard exit=0, last line: smoke: all 192 passed
Verdict: RED, as expected
```

The parse step catches it too: `/bin/bash -n tests/smoke.sh` exits 2 on the `main` file and 0 on this branch.

## Negative control: workflow lint

```
Command: actionlint
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/runs-on: macos-26/runs-on: macos-2600/' .github/workflows/ci.yml
Exit: 1 (under mutation, RED expected)
Output:
.github/workflows/ci.yml:36:14: label "macos-2600" is unknown. ... [runner-label]
Restore: git checkout HEAD -- .github/workflows/ci.yml
Exit: 0 (green after restore)
Verdict: RED, as expected
```

## Stays local

The live Quick Look panel, the Safari extension, `scripts/layout-check` and the screenshot scripts need a desktop session, an installed app or a specific browser. `docs/dev/testing.md` lists them.

## Reproduce

Follow `CONTRIBUTING.md` from a fresh clone. For the false green: `git show origin/main:tests/smoke.sh > /tmp/old.sh` (before this PR) and run `/bin/bash -n /tmp/old.sh`.
