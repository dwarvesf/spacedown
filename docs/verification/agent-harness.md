# Proof: agent harness

The agent harness works for any contributor. Kit hooks in `.claude/settings.json` go through `scripts/agent-kit-hook.sh` and do nothing without the kit. A repo-local guard (`scripts/agent-guard.sh`) refuses a push to `main`, a force push or `--mirror`, `--no-verify`, `core.hooksPath`, a commit on `main`, and an edit or commit of a contract-frozen file off a `contract/` branch. The guard is a seatbelt, not a boundary: its known gaps are in its header and in `AGENTS.md`, and the ruleset on `main` is the real control. `scripts/check.sh` runs every local check in one command. A lesson index, the `ship-pr` and `ui-change` playbooks, and the doors table in `AGENTS.md` complete it.

## Green run

The whole local gate, after the last commit (`bash scripts/check.sh`):

```
Command: bash scripts/check.sh
Exit: 0
Output:
ok    bash -n on tests/*.sh and the agent scripts
ok    smoke suite (/bin/bash tests/smoke.sh) (smoke: all 192 passed)
ok    katex-one-test.sh (katex-one-test: 9 passed, 0 failed)
ok    size-budget-test.sh (size-budget-test: 5 passed, 0 failed)
ok    hljs-bundle-test.js (hljs-bundle-test: all passed)
ok    owner check (owners: 41 scripts and workflows, all owned)
ok    pr-shape-test.sh (pr-shape-test: 18 passed, 0 failed)
ok    agent guard test (failures: 0)
ok    agent kit hook test (failures: 0)
ok    check.sh test (failures: 0)
ok    lesson index (lessons: index ok (989 characters))
ok    actionlint
note  not run here: the app build (NO_INSTALL=1 integrations/build-safari.sh) and the live Quick Look panel (in a VM or a clean macOS user)
check: 0 failed
exit 0
Verdict: PASS
```

The kit hook wrapper with `HOME` pointing at an empty directory (every settings command exits 0, the kit ones print nothing), then with the real kit installed (`AGENT_TEST_REAL_KIT=1`, every kit command run from a scratch git repo):

```
Command: bash scripts/test-agent-kit-hook.sh
Exit: 0
Output: PASS  empty HOME: silent exit 0: agent-kit-hook.sh output-offload.sh ... (11 kit commands, 3 others exit 0), failures: 0
Verdict: PASS

Command: AGENT_TEST_REAL_KIT=1 bash scripts/test-agent-kit-hook.sh
Exit: 0
Output: PASS  real kit: exit 0: agent-kit-hook.sh output-offload.sh ... agent-kit-hook.sh context-hints.sh (11 of 11), failures: 0
Verdict: PASS
```

The guard run the way Claude Code runs it (hook JSON on stdin, from a feature branch). Exit 2 is a block; the first lines of stderr follow:

```
Command: git push origin main
Exit: 2
agent-guard: a push to main skips review: nothing lands on main except through a PR.
Fix: git switch -c <type>/<slug>; git push -u origin <type>/<slug>; gh pr create

Command: git push origin "main"
Exit: 2
agent-guard: a push to main skips review: nothing lands on main except through a PR.
Fix: git switch -c <type>/<slug>; git push -u origin <type>/<slug>; gh pr create

Command: git push --force origin feat/x
Exit: 2
agent-guard: a force push rewrites history that others may have pulled.
Fix: push a new commit, or merge origin/main into the branch; a maintainer force-pushes by hand when it is truly needed

Command: git commit --no-verify -m x
Exit: 2
agent-guard: --no-verify skips the repo's hooks and checks.
Fix: fix what the check reports, then run the command again without the flag

Command: git -c core.hooksPath=/dev/null commit -m x
Exit: 2
agent-guard: setting core.hooksPath switches the repo's hooks and checks off.
Fix: leave core.hooksPath alone; fix what the check reports

Command: Edit scripts/agent-guard.sh (always frozen; feature branch)
Exit: 2
agent-guard: scripts/agent-guard.sh is frozen by docs/contract-r1.md: a change goes through its own contract PR, never inside a feature PR.
Fix: git switch -c contract/<slug>; change only the frozen file there; open the PR and say why in its body (AGENTS.md, 'The release contract')

Command: git push -u origin feat/x (a normal push)
Exit: 0


Command: git status (a normal command)
Exit: 0


Command: Edit README.md (a normal edit)
Exit: 0
```

The guard test has hundreds of cases: each blocked command above and many variants (abbreviated options, `@` and `@{-1}` destinations, quoted words, a list edited in the working tree, a local branch named `origin/main`), and the normal commands that must pass.

## Negative control

Each block is one mutation of the guard, the wrapper, the settings file, the frozen list or `check.sh`: run the test green, break one thing, show it red, restore with `git checkout HEAD -- <file>`, show it green. The work was committed first, so the restore is a clean checkout.

```
## guard: push destination is not resolved (@, @{-1})
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: [ "$dst" = "main" ] || [ "$full" = "refs/heads/main" ] && block "$msg" "$fix"  ->  :
Exit: 1 (under the mutation)  Output: 8 FAIL lines; first: FAIL  push HEAD while on main: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: a bare push on main is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: [ "$tags" -eq 0 ] && [ "$cur" = "main" ] && block "$msg" "$fix"  ->  :
Exit: 1 (under the mutation)  Output: 4 FAIL lines; first: FAIL  bare git push on main: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: force push is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: if long_opt "$a" force || long_opt "$a" force-with-lease || long_opt "$a" force-if-includes; then force=1; continue; fi  ->  :
Exit: 1 (under the mutation)  Output: 20 FAIL lines; first: FAIL  push --force: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: long options match exact names only
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: [ "${#n}" -ge "${3:-4}" ] && [ "${2#"$n"}" != "$2" ]  ->  [ "$n" = "$2" ]
Exit: 1 (under the mutation)  Output: 22 FAIL lines; first: FAIL  push --forc: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: --mirror is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: long_opt "$a" mirror 1 &&  ->  false &&
Exit: 1 (under the mutation)  Output: 8 FAIL lines; first: FAIL  push --mirror: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: --mirror abbreviations need 4 characters
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: long_opt "$a" mirror 1 &&  ->  long_opt "$a" mirror 4 &&
Exit: 1 (under the mutation)  Output: 4 FAIL lines; first: FAIL  push --m: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: --no-verify is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: long_opt "$a" no-verify && block  ->  false && block
Exit: 1 (under the mutation)  Output: 20 FAIL lines; first: FAIL  commit --no-verify: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: commit -n is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: *n*) block "git commit -n  ->  *nZ*) block "git commit -n
Exit: 1 (under the mutation)  Output: 6 FAIL lines; first: FAIL  commit -n: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: core.hooksPath is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh:     core.hookspath)  ->      core.hookspathx)
Exit: 1 (under the mutation)  Output: 16 FAIL lines; first: FAIL  -c "core.hooksPath=/x": expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: frozen edits are allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: is_frozen "${rel#/}" "$(frozen_patterns "$top")" && frozen_block "${rel#/}" "$d"  ->  :
Exit: 1 (under the mutation)  Output: 30 FAIL lines; first: FAIL  Edit a frozen file, feature branch: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: frozen files staged at commit are allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: is_frozen "$f" "$pats" && frozen_block "$f" "$dir"  ->  :
Exit: 1 (under the mutation)  Output: 14 FAIL lines; first: FAIL  commit with a frozen file staged, feature branch: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: the guard, its list and settings are not always frozen
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: printf '%s\n' scripts/agent-guard.sh scripts/agent-frozen-paths.txt .claude/settings.json  ->  printf '%s\n' none
Exit: 1 (under the mutation)  Output: 10 FAIL lines; first: FAIL  Edit the guard script: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: the list is read from the working tree
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: if git -C "$1" rev-parse -q --verify refs/remotes/origin/main  ->  if false
Exit: 1 (under the mutation)  Output: 6 FAIL lines; first: FAIL  list edited in the working tree: frozen file still blocked: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: the list is read through a short ref name
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: show refs/remotes/origin/main:scripts  ->  show origin/main:scripts
Exit: 1 (under the mutation)  Output: 2 FAIL lines; first: FAIL  a local branch named origin/main does not shadow the list: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: ../ is not folded
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: ..) [ "${#out[@]}" -eq 0 ] || out=("${out[@]:0:${#out[@]}-1}") ;;  ->  ..) ;;
Exit: 1 (under the mutation)  Output: 2 FAIL lines; first: FAIL  Write a new frozen file under a missing directory: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: quote characters are not removed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: s/[\"']//g  ->  
Exit: 1 (under the mutation)  Output: 12 FAIL lines; first: FAIL  push origin "main": expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: a commit on main is allowed
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: [ "$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)" = "main" ] &&  ->  false &&
Exit: 1 (under the mutation)  Output: 8 FAIL lines; first: FAIL  commit on main: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## guard: a missing jq is allowed through
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-guard.sh: brew install jq" >&2; exit 2; }  ->  brew install jq" >&2; exit 0; }
Exit: 1 (under the mutation)  Output: 1 FAIL lines; first: FAIL  no jq: expected exit 2 and the message, got rc 0
Restore: git checkout HEAD -- scripts/agent-guard.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## kit wrapper: the absence test is removed
Command: bash scripts/test-agent-kit-hook.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-kit-hook.sh: [ -f "$kit/hooks/anchor-root.sh" ] && [ -f "$kit/hooks/$hook" ] || exit 0  ->  :
Exit: 1 (under the mutation)  Output: 12 FAIL lines; first: FAIL  empty HOME: exit 127: bash "$CLAUDE_PROJECT_DIR/scripts/agent-kit-hook.sh" output-offload.sh
Restore: git checkout HEAD -- scripts/agent-kit-hook.sh
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## settings: a kit hook calls the kit directly
Command: bash scripts/test-agent-kit-hook.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in .claude/settings.json: bash \"$CLAUDE_PROJECT_DIR/scripts/agent-kit-hook.sh\" context-hints.sh  ->  bash $HOME/.claude/dwarves-kit/hooks/context-hints.sh
Exit: 1 (under the mutation)  Output: 2 FAIL lines; first: FAIL  a settings command names dwarves-kit directly: bash $HOME/.claude/dwarves-kit/hooks/context-hints.sh
Restore: git checkout HEAD -- .claude/settings.json
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## frozen list: tests/smoke.sh dropped
Command: bash scripts/test-agent-guard.sh
Exit: 0 (green before the mutation)  Output: failures: 0
Mutation in scripts/agent-frozen-paths.txt: 
tests/smoke.sh
  ->  

Exit: 1 (under the mutation)  Output: 9 FAIL lines; first: FAIL  Edit with a relative path: expected exit 2, got 0
Restore: git checkout HEAD -- scripts/agent-frozen-paths.txt
Exit: 0 (green after the restore)  Output: failures: 0
Verdict: RED, as expected

## check.sh: a unit test fails
Command: bash scripts/check.sh --quick
Exit: 0 (green before the mutation)  Output: check: 0 failed
Mutation in tests/size-budget-test.sh: #!/usr/bin/env bash
  ->  #!/usr/bin/env bash
exit 1

Exit: 1 (under the mutation)  Output: 1 FAIL lines; first: FAIL  size-budget-test.sh
Restore: git checkout HEAD -- tests/size-budget-test.sh
Exit: 0 (green after the restore)  Output: check: 0 failed
Verdict: RED, as expected
```

## Not proven

- The guard was not run inside a live Claude Code session here. It was fed the hook JSON a session sends, through the same command line `.claude/settings.json` uses.
- A frozen file edit is judged against `scripts/agent-frozen-paths.txt` on `origin/main`. That file arrives with this PR, so until it merges `origin/main` has no list and only the three built-in paths (the guard, the list, the settings file) are frozen; the full list is covered by the test fixtures, which build a repo with a remote.
- The guard stops accidents, not a determined agent (see Known gaps in `AGENTS.md`).
- The app build and the live Quick Look panel are not touched by this change and were not run.

## Reproduce

```
bash scripts/check.sh
AGENT_TEST_REAL_KIT=1 bash scripts/test-agent-kit-hook.sh     # on a machine with the kit
bash scripts/test-agent-guard.sh
```
