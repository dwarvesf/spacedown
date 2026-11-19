# Proof of Done, dev-ready

The repo gets what an outside developer needs: a self-contained `AGENTS.md`, `CONTRIBUTING.md`, a docs index with development, testing and release pages, issue and PR templates, and CI on GitHub-hosted macOS runners (the repo is public, so fork PRs never reach our hardware).

## Green run (local, before CI)

The suites CI runs, run first in a clean macOS VM with node, pandoc, entr and Google Chrome:

```
Command: bash tests/smoke.sh
Exit: 0
Output: smoke: all 192 passed
Verdict: PASS
```

```
Command: bash tests/katex-one-test.sh; bash tests/size-budget-test.sh; node tests/hljs-bundle-test.js
Exit: 0
Output:
katex-one-test: 9 passed, 0 failed
size-budget-test: 5 passed, 0 failed
hljs-bundle-test: all passed
Verdict: PASS
```

```
Command: actionlint
Exit: 0
Output: (no findings)
Verdict: PASS
```

## Negative control

A runner label that does not exist must turn the workflow lint red.

```
Command: actionlint
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/runs-on: macos-26/runs-on: macos-2600/' .github/workflows/ci.yml
Exit: 1 (under mutation, RED expected)
Output:
.github/workflows/ci.yml:36:14: label "macos-2600" is unknown. ... [runner-label]
.github/workflows/ci.yml:69:14: label "macos-2600" is unknown. ... [runner-label]
Restore: git checkout HEAD -- .github/workflows/ci.yml
Exit: 0 (green after restore)
Verdict: RED, as expected
```

## Reproduce

`bash tests/smoke.sh`, the three unit tests above, and `actionlint` from the repo root.
