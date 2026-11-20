# release-defaults

`scripts/check.sh` now runs `tests/release-notes-test.sh`, the one unit test it skipped, so the local command covers what `docs/dev/testing.md` lists. AGENTS.md also stops saying `release.sh` deletes older releases: it keeps them by default and `PRUNE_OLD_RELEASES=1` opts in to deleting them (the script and `docs/dev/release.md` already said so).

## Green run

```
Command: bash scripts/check.sh
Exit: 0
Output:
  ok    release-notes-test.sh (release-notes-test: 7 passed, 0 failed)
  ok    check.sh test (failures: 0)
  check: 0 failed
Verdict: PASS
```

## Negative control

```
Command: bash scripts/check.sh --quick
Exit: 0 (green before the mutation, committed first)
Mutation: sed -i '' 's/^## \[1.2.0\]/## [1.2.0-x]/' CHANGELOG.md (the release version loses its section)
Exit: 1 (under the mutation)
Output: release-notes-test: 6 passed, 1 failed
        FAIL  release-notes-test.sh
        check: 1 failed
Restore: git checkout HEAD -- CHANGELOG.md
Exit: 0 (green after the restore)
Output: ok    release-notes-test.sh (release-notes-test: 7 passed, 0 failed)
        check: 0 failed
Verdict: RED, as expected
```

## Reproduce

```
bash scripts/check.sh
bash scripts/test-check.sh
```
