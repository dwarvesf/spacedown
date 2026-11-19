# Proof files

One proof file per PR that changes behavior: `docs/verification/<slug>.md`, where the slug is the branch name without its type (`fix/table-gap` writes `table-gap.md`). Behavior means any changed file that is not documentation. A proof file is a dated record: add a new one, never rewrite an old one. This README is not a proof.

## What goes in one

1. One paragraph: what changed and why.
2. `## Green run`: each command you ran, with its exit code, trimmed real output and a verdict.
3. `## Negative control`: break the change on purpose, show the test go red, restore it, show it green again. This shows the test can fail.
4. `## Reproduce`: the commands someone else runs to see the same result.
5. A change to what the Quick Look panel or a page shows: before and after screenshots under `docs/verification/<slug>/`, linked from the file.

## Run block

````
```
Command: bash tests/smoke.sh --only docx
Exit: 0
Output: smoke: all 12 passed
Verdict: PASS
```
````

Paste real output, trimmed to the lines that matter. Never "should pass".

## Negative control block

````
```
Command: node integrations/safari/quick-look/test-boxdraw.js
Exit: 0 (green before the mutation)
Mutation: <the one edit that breaks the change, e.g. delete the new rule>
Exit: 1 (under the mutation)
Output: boxdraw: 1 FAILED
Restore: git checkout HEAD -- <file>
Exit: 0 (green after the restore)
Verdict: RED, as expected
```
````

Commit before the negative control so the restore is a clean checkout.

## Tooling

The optional agent kit's ship gate (`.kit.toml`) reads this folder: the presence of this README opts the repo into its proof-of-done check. Nothing here needs the kit.
