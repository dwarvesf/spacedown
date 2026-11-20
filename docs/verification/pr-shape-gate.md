# Verification: pr-shape-gate (2026-11-21)

Merge-time controls. A `PR shape` workflow runs the base branch's `scripts/pr-shape.sh` on every PR: conventional title, a proof file with a negative control or a `no-proof:` line, and a real number in any `Closes #<n>`. CI moves its docs filter from the trigger into a `changes` job, so the run always starts and a `CI summary` job always reports. `.github/CODEOWNERS` gives every script and workflow its own line, and `scripts/check-owners.sh` (run in CI) fails when one is missing. Decisions: [../implementation-notes/pr-shape-gate.md](../implementation-notes/pr-shape-gate.md).

## Green run

```
Command: /bin/bash scripts/pr-shape-test.sh
Exit: 0
Output:
PASS  issue claim with a PR URL (exit 1)
PASS  missing BASE_SHA exits 2
pr-shape-test: 18 passed, 0 failed
Verdict: PASS
```

The 18 cases: seven green shapes (full proof file, docs with `no-proof:`, config with `no-proof:`, valid `Closes #12` and issue URL, prose "fixes" is no claim, template comments ignored, a 72-character title) and ten that must fail on a named check (no type, unknown type, 73 characters, no proof, a proof without a negative control, README.md as proof, docs-only without `no-proof:`, a reason under 10 characters, `Closes #<n>`, a pull URL as the issue), plus bad usage exiting 2.

```
Command: /bin/bash scripts/check-owners.sh
Exit: 0
Output: owners: 33 scripts and workflows, all owned
Verdict: PASS
```

```
Command: actionlint; shellcheck -S warning scripts/check-owners.sh scripts/pr-shape.sh scripts/pr-shape-test.sh
Exit: 0 (both)
Output: (none)
Verdict: PASS
```

Dry run of the script against the twelve PRs merged before it (#76 to #87): every title passes. Most fail the proof check, as intended: older proof files predate the `Verdict: RED` line, and docs-only PRs carried no `no-proof:` line.

## Negative control

The pr-shape tests, with the title check broken (`title_re='.*'`), then restored:

```
Command: /bin/bash scripts/pr-shape-test.sh
Exit: 1 (under the mutation)
Output: pr-shape-test: 16 passed, 2 failed
Restore: git checkout HEAD -- scripts/pr-shape.sh
Exit: 0 (after the restore)
Verdict: RED, as expected
```

The 73-character case still fails under that mutation because the length test is separate; the two missing-type cases go red.

The pr-shape tests, with the proof check forced to pass (`if true; then` in place of the `no-proof:` test), then restored:

```
Command: /bin/bash scripts/pr-shape-test.sh
Exit: 1 (under the mutation)
Output:
FAIL  no-proof reason under 10 characters: no FAIL line for the proof check
pr-shape-test: 13 passed, 5 failed
Restore: git checkout HEAD -- scripts/pr-shape.sh
Exit: 0 (after the restore)
Verdict: RED, as expected
```

The owner check, with the `/scripts/release.sh` line removed and a line added for a file that does not exist:

```
Command: /bin/bash scripts/check-owners.sh
Exit: 1 (under the mutation)
Output:
owners: FAIL (.github/CODEOWNERS)
  line names a path that is not tracked: /scripts/gone.sh
  no owner line: scripts/release.sh (add: /scripts/release.sh @<owner>)
Restore: git checkout HEAD -- .github/CODEOWNERS
Exit: 0 (after the restore)
Verdict: RED, as expected
```

This branch judged by its own gate before this proof file existed:

```
Command: PR_TITLE='ci: pr-shape check, CI summary and code owners' PR_BODY='Adds the gate.' BASE_SHA=<merge base> HEAD_SHA=<head> bash scripts/pr-shape.sh
Exit: 1
Output:
ok    title: a conventional commit subject
FAIL  proof: a behavior path changed and the PR adds or changes no proof file under docs/verification/
ok    issue: the body claims no issue
pr-shape: 1 failed
Verdict: RED, as expected
```

## Reproduce

```bash
bash scripts/pr-shape-test.sh
bash scripts/check-owners.sh
PR_TITLE="$(gh pr view <n> --json title -q .title)" PR_BODY="$(gh pr view <n> --json body -q .body)" \
  BASE_SHA=<base sha> HEAD_SHA=<head sha> bash scripts/pr-shape.sh
```

## Ruleset on main (2026-11-21, added after #89 merged)

`main` is green with the new checks: push run 44796250273 on 03730ac (Owners and changed paths, Lint workflows, Build, Tests and CI summary all `success`). Then a repository ruleset, id `27752467`, created with `gh api -X POST repos/consolelabs/spacedown/rulesets`:

| Rule | Setting |
|---|---|
| Target | the default branch (`~DEFAULT_BRANCH`), enforcement active |
| Pull request | required; 0 approvals (one maintainer); merge method squash only |
| Required checks | `PR shape` and `CI summary`, both from GitHub Actions (integration 15368); up to date with main not required |
| Force push, deletion | blocked |
| Bypass | the repository admin role, mode always, so the maintainer is never locked out |

```
Command: gh api repos/consolelabs/spacedown/rules/branches/main --jq '.[]|[.type,.ruleset_id]|@tsv'
Exit: 0
Output:
deletion                27752467
non_fast_forward        27752467
pull_request            27752467
required_status_checks  27752467
Verdict: PASS
```

### Green run: #89

PR #89 (this change) before the ruleset: `PR shape` run 44795678460 passed (it had no base copy yet and used its own, with a notice); CI run 44795678272 passed every job, `CI summary` included.

```
Command: gh pr checks 89
Exit: 0
Output:
Build the app (unsigned, not installed)  pass
CI summary                               pass
Lint workflows                           pass
Owners and changed paths                 pass
PR shape                                 pass
Tests (smoke suite and unit tests)       pass
Verdict: PASS
```

### Negative control: #90, a throwaway PR the ruleset must block

A docs-only PR with a title that is not a conventional commit and a valid `no-proof:` line, so only the title check can fail. `PR shape` run 44796773183 ran the base copy (no fallback notice) and failed; CI run 44796773179 skipped the macOS jobs on the docs-only change and `CI summary` still passed. The merge was refused. The PR was then closed unmerged and its branch deleted.

```
Command: gh pr checks 90; gh pr view 90 --json mergeStateStatus; gh pr merge 90 --squash
Exit: 1
Output:
PR shape                                 fail
CI summary                               pass
Build the app (unsigned, not installed)  skipping
Tests (smoke suite and unit tests)       skipping
FAIL  title: "Throwaway negative control for the main ruleset" is not type(scope): subject with type feat, fix, refactor, docs, test, chore or ci and 72 characters or less (47 now)
{"isDraft":false,"mergeStateStatus":"BLOCKED","mergeable":"MERGEABLE"}
X Pull request consolelabs/spacedown#90 is not mergeable: the base branch policy prohibits the merge.
Verdict: RED, as expected
```

The maintainer's token can bypass (`current_user_can_bypass: always`), so the refusal above is the ruleset's verdict shown to a normal merge; `--admin` was never used.
