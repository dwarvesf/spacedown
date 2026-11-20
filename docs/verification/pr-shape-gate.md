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
