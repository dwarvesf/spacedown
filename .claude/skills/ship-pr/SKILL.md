---
name: ship-pr
description: Take a Spacedown change from an issue or an idea to a PR that is green and ready for a maintainer. Use when asked to do, fix, build or ship something in this repo, or when a change is ready to push. Covers branch, worktree, proof file, scripts/check.sh, the PR body, CI and what you stop and ask.
---

# Ship a PR

Run every command from the repo root of your worktree. The rules behind each step are in `AGENTS.md`; this file holds the commands only. Needs `git`, `gh`, and the tools in `CONTRIBUTING.md`, "Prerequisites". No plugin.

## 1. Size the work and check the doors

- Tiny (a typo, a comment, a doc line), normal (one feature or fix) or full: `AGENTS.md`, "Size the work".
- Read the "Doors" table in `AGENTS.md`. If your change touches a door (a frozen file, a release or signing script, a bundle id, LICENSE or TRADEMARKS, a CI workflow), stop and ask a maintainer before you edit. A full change posts its plan in the PR body first.

## 2. Branch in a worktree

```sh
git fetch origin main
git worktree add .claude/worktrees/<slug> -b <type>/<slug> origin/main
cd .claude/worktrees/<slug>
```

- `<type>` is feat, fix, refactor, docs, test, chore or ci. The slug is two to five kebab-case words. A change to a contract-frozen file uses `contract/<slug>` and its own PR.
- Never commit on `main`, never push to it. The agent hook (`scripts/agent-guard.sh`) refuses both.

## 3. Build

- Make the change. Run the command for your area from `AGENTS.md`, "Commands". While you iterate, `bash scripts/check.sh --quick` runs the unit tests and the render core tests; the full run is step 5.
- One logical change per commit. Subject `type(scope): subject`, 72 characters or less. Stage explicit paths. Never stage `build/`, rendered `.html`, `.DS_Store`, keys or profiles.
- No em or en dashes in code, comments or docs. Fix any doc your change makes wrong in the same PR.
- A change to what the panel or a page shows: run the `ui-change` skill too.

## 4. Proof

A behavior change (any changed file that is not documentation) adds `docs/verification/<slug>.md`, as `docs/verification/README.md` says: a `Command:` / `Exit:` / `Output:` / `Verdict:` block with real output, and a negative control. Commit the work first, then break one thing on purpose, show the test go red, restore with `git checkout HEAD -- <file>`, show it green.

A docs-only or config-only PR needs no proof file. Put this line in the PR body instead, with a reason of ten or more characters:

```
no-proof: <why no behavior changes>
```

## 5. Check before you push

```sh
bash scripts/check.sh
```

It runs the syntax check, the smoke suite under `/bin/bash`, the unit tests, the agent harness tests and `actionlint` when installed. A red check prints `FAIL <reason>` and a `fix:` line: do what it says, rerun. Exit 0 is the bar. Then run what it says it did not run (the app build for Swift, Xcode project or Quick Look resource changes: `NO_INSTALL=1 integrations/build-safari.sh`).

## 6. Open the PR

```sh
git push -u origin <type>/<slug>
gh pr create --title "<type(scope): subject>" --body-file <file>
```

- Fill the body file from `.github/pull_request_template.md`: What, Demo, Proof, Notes, and the license checkbox. The title becomes the commit subject on `main`.
- Say in Notes what you did not test and why. A change that needs a maintainer's yes (`AGENTS.md`, "Stop and ask") says so there.

## 7. CI, then stop

```sh
gh pr checks <n> --watch
```

- Red: read `gh run view <run-id> --log-failed`, fix, push, watch again. A first-time contributor's run waits for a maintainer to approve it.
- All green: a maintainer merges (squash). Do not merge your own PR unless a maintainer told you to. Never use `--admin`, never skip a check, never edit `tests/known-failures.txt` without a yes.
- After the merge, from the main checkout: `git worktree remove .claude/worktrees/<slug>` and `git branch -d <type>/<slug>`.

## Lessons

When your PR paid for a lesson, add a note in the same PR: `AGENTS.md`, "Lessons".

## Done when

`bash scripts/check.sh` exits 0, the proof file (or the `no-proof:` line) is in the PR, `gh pr checks <n>` is all green, and the PR body is filled from the template.
