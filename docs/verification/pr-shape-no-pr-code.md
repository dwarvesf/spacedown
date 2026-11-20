# Verification: pr-shape-no-pr-code (2026-11-21)

The first `PR shape` workflow ran the PR's `scripts/pr-shape-test.sh` in the same job, before the base copy of the gate. A PR could make that script overwrite `base/scripts/pr-shape.sh` and pass any title. This change runs no PR code in that job (the gate's tests move to the `Owners and changed paths` job in `ci.yml`, which `CI summary` gates), and the gate step now fails closed unless the file on disk hashes to the base commit's blob. Decisions: [../implementation-notes/pr-shape-gate.md](../implementation-notes/pr-shape-gate.md).

## Negative control: the hole, before this change

Throwaway PR #93: a title that is not a conventional commit, and a `scripts/pr-shape-test.sh` that overwrites the base copy with `exit 0`. Run 44797887579 on the old workflow:

```
Command: gh run view 44797887579 --log (PR shape job of #93)
Exit: 0 (the job passed: the gate was bypassed)
Output:
hostile: replaced /home/runner/work/spacedown/spacedown/base/scripts/pr-shape.sh
pr-shape: 0 failed (replaced by the PR)
Verdict: RED, as expected (the check passed a bad title; this is the defect the change fixes)
```

## Green run

The integrity check from the new gate step, against a local clone of the base:

```
Command: integrity check, untouched base copy
Exit: 0
Output: base copy verified (cd76f1399610e5287c1044b9349bf1f21158d685)
Verdict: PASS
```

The same check with the base copy overwritten, then restored:

```
Command: integrity check, base copy overwritten
Exit: 1 (under the mutation)
Output: ::error::base/scripts/pr-shape.sh is not the base commit's copy (06bd986563d4c79bcdeb334e9502a09a452f80e4, want cd76f1399610e5287c1044b9349bf1f21158d685)
Restore: git checkout -- scripts/pr-shape.sh
Exit: 0 (after the restore)
Verdict: RED, as expected
```

```
Command: bash scripts/pr-shape-test.sh; actionlint
Exit: 0
Output: pr-shape-test: 18 passed, 0 failed
Verdict: PASS
```

## After merge

#93 is re-run on the fixed workflow from `main`; the result is added below when it lands.

### #93 on the fixed workflow (added after #94 merged as e5f783c)

`main` merged into #93 (head 6e50e95). `PR shape` run 44798776050 ran no PR code and judged the title with the base copy; the hostile script ran only in CI run 44798776098, where there is no base copy to replace.

```
Command: gh run view 44798776050 --log; gh run view 44798776098 --log; gh pr view 93 --json mergeStateStatus; gh pr merge 93 --squash
Exit: 1
Output:
FAIL  title: "Throwaway: a PR test script that rewrites the gate" is not type(scope): subject with type feat, fix, refactor, docs, test, chore or ci and 72 characters or less (50 now)
pr-shape: 1 failed
hostile: no base copy to replace
{"mergeStateStatus":"BLOCKED"}
X Pull request consolelabs/spacedown#93 is not mergeable: the base branch policy prohibits the merge.
Verdict: PASS (the gate holds: the check fails and the merge is blocked)
```

#93 was then closed unmerged and its branch deleted.

## Reproduce

Open a PR whose `scripts/pr-shape-test.sh` writes to `$GITHUB_WORKSPACE/base/scripts/pr-shape.sh` and whose title is not a conventional commit: `PR shape` fails on the title.
