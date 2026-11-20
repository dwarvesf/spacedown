# Implementation notes: merge-time controls (pr-shape, required checks, owners)

Only the decisions the brief did not make. The brief: a `pr-shape` check on every PR, requirable test and build checks, CODEOWNERS with an owner check, then a ruleset on `main`.

## Decisions

- **pr-shape is its own workflow, `.github/workflows/pr-shape.yml`.** It listens to `edited` so a fixed title or body re-runs it (a plain re-run replays the old event payload). Inside `ci.yml` an `edited` event would either re-run the macOS jobs on every body edit, or skip them and post a newer green summary over an older red one on the same commit.
- **The gate script comes from the base commit.** The job checks out the PR into `pr/` and the base commit into `base/`, then runs `base/scripts/pr-shape.sh` inside `pr/`. Title and body come from the event payload through `env:`. The script reads only git objects and those variables, and the job runs no PR code, so the PR checkout cannot change the verdict. When the base has no script yet (the PR that adds it), the job uses the PR's copy and says so.
- **The gate's own tests run in `ci.yml`, not in the PR shape job.** The first version ran the PR's `scripts/pr-shape-test.sh` in the same job before the gate; a PR could make that script overwrite `base/scripts/pr-shape.sh` and pass any title. Throwaway PR #93 showed it; the fix moved the tests to the `changes` job, which `CI summary` gates.
- **Limit of that design.** Under `pull_request` the workflow file itself comes from the PR's merge commit, so a PR can still edit `pr-shape.yml`. `pull_request_target` would close that but runs with a write token next to fork code, so it stays out. CODEOWNERS and the maintainer reading workflow diffs cover the gap.
- **Three checks only:** title, proof, issue link. Board, changelog, docs layout and shellcheck checks seen in other repos have no counterpart here.
- **Title types** are the ones CONTRIBUTING.md lists: feat, fix, refactor, docs, test, chore, ci. Scope is optional. Limit 72 characters.
- **Proof rule.** A `no-proof: <reason of 10+ characters>` line passes any PR. Otherwise a `docs/verification/*.md` file (not README.md) in the diff must hold an `Exit:` line, a line starting `Verdict: RED`, and the words "negative control". A behavior PR without either fails, and so does a docs-only PR: the marker makes "no proof" an explicit, countable choice.
- **Behavior path** follows the kit's proof gate (any changed file that is not documentation: `*.md`, `*.txt`, `.kit.toml`, images and PDFs under `docs/`). This is not the same list as the CI docs filter below: `README.md` is documentation for proof, but CI still runs on it because the MCP test reads it.
- **Issue link.** A claim is a closing keyword (close, fix, resolve and their forms) followed by `#`, `issue #`, or a GitHub URL. Plain prose such as "fixes the table gap" is not a claim. A claim must name `#<number>`, `owner/repo#<number>` or a `.../issues/<number>` URL. The check is format only: it does not ask the API whether the issue exists.
- **HTML comments are stripped** from the body first. The template's comments say `Closes #<n>` and would otherwise count as a claim.
- **CI docs filter moved from the trigger into a `changes` job.** A workflow-level `paths-ignore` skips the whole run, so a required check never reports and a docs-only PR waits forever. The job diffs `HEAD^1..HEAD` (the PR merge commit, or the squash commit on `main`); with no parent or on a manual run it runs everything. One list, in the job.
- **`CI summary` is the required CI check.** It runs with `if: always()`, fails when `changes` did not succeed, and fails when any other job failed or was cancelled. Skipped counts as passing.
- **CODEOWNERS lists every script and workflow by path**, not a `*` or a directory line, which would make the owner check vacuous. A PR that adds a script adds its line. Counted as a script: every tracked file under `scripts/`, `bin/` and `.github/workflows/` (except Markdown), plus every tracked `*.sh`, `*.py` and `*.mjs` outside `docs/` (proof folders hold dated helper scripts).
- **timeout-minutes 20** on every job. Test and build took two to three minutes in recent runs.

- **Ruleset targets `~DEFAULT_BRANCH`**, not the literal `main`, so a rename keeps it.
- **Required checks need not be up to date with `main`.** Several PRs land in parallel; requiring a rebase before each merge would re-run the macOS jobs for every one. The squash merge still runs CI on `main`.
- **Admin bypass mode is `always`.** One maintainer, no second account: anything narrower risks a lockout. The negative control therefore shows the block through a normal merge (`gh pr merge --squash` refused), never `--admin`.
- **An open PR from before the ruleset** has no `PR shape` run until its next push or edit, and stays blocked until then.

## Open questions

- Should pr-shape also reject em and en dashes in added lines? AGENTS.md bans them; no check enforces it.
- Should the issue check ask the API that the number is an issue, not a PR?
