# Implementation notes: agent harness

Delta from the brief only.

## Decisions

- Kit hooks go through one wrapper, `scripts/agent-kit-hook.sh <hook> [args]`. It exits 0 when the kit or the named hook is missing, and otherwise execs the kit's `anchor-root.sh` with the same arguments. One tested script beats ten copies of an inline `test -f`. `DWARVES_KIT_DIR` overrides the kit path, used by the tests.
- The guard is one script for two tool kinds: `Bash` (push, force, `--no-verify`, commit on main, frozen files staged at commit time) and `Edit|Write|MultiEdit|NotebookEdit` (frozen file edits). Editing at tool time gives the early message; the commit-time check catches a `sed -i` or `cp` that the edit hook never saw.
- The frozen list lives in `scripts/agent-frozen-paths.txt`, not parsed out of `docs/contract-r1.md` (prose with `QL` and `APP` shorthands). `scripts/test-agent-guard.sh` checks that every entry still exists and that the contract still names its file, so a rename or a new frozen file fails a test instead of silently opening a hole.
- A frozen file may change only on a branch named `contract/<slug>`. There is no environment bypass: a bypass the agent can set is not a guard. The second line is review and CI.
- Force pushes are blocked on every branch, not only main. Fix text: push a new commit or merge `main` in.
- `check.sh` runs the commands AGENTS.md lists and `docs/dev/testing.md` marks as run by CI. It does not run the app build, the live panel or any release script. A missing `actionlint` is a note, not a failure (the brief says "if installed"). A missing `node` fails, as the smoke suite does.

- The guard does not block a bare `gh pr merge`: this repo has no merge script to point at, and a maintainer merges. The door table in AGENTS.md is prose; the guard enforces the frozen-file row only, from `scripts/agent-frozen-paths.txt`.
- Lessons seeded in `.claude/memory/` restate pitfalls the existing docs already name (bash 3.2, the panel runs no scripts, `build-safari.sh` installs). No new incident is claimed.
- Quoted strings with a space are folded to one word before the guard reads git flags, so `git commit -m "never use --no-verify"` passes.

## Tradeoffs

- The guard is text matching on the command line (the header lists the limits), so it cannot see a command built in a variable or inside a script. It names the fix at the moment of the mistake; it is not a wall.
- `check.sh` takes about a minute, mostly the smoke suite. `--quick` skips the smoke suite for an inner loop and says so.

## Open questions for a maintainer

- The kit's adopt step (`--refresh`) may rewrite `.claude/settings.json` and drop the wrapper. `scripts/test-agent-kit-hook.sh` fails on a settings command that calls the kit directly, so the drift is caught.
- CONTRIBUTING.md lists the branch types without `contract`; another change owns that file. Add `contract` there once it lands. AGENTS.md already names it.
- The PR-shape job (another change) must accept a `contract/` branch prefix.
