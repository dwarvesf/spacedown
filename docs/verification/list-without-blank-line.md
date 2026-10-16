# Proof of Done, list-without-blank-line

A list written right under a line of text (`**1. Pick**` then `- [ ] item`) rendered as literal `- [ ]` text in the browser and the Safari drop extension, while Quick Look (marked) showed a list. The pandoc reader now carries `+lists_without_preceding_blankline`, so all three surfaces agree.

**Date:** 2026-10-16 · **Lane:** normal · **Host:** Mac-mini-2 · **Branch:** `fix/md-list-blankline`

## Green run

```
Command: bash tests/smoke.sh
Exit: 0
Output:
[list] a list right under a line of text is a list, with task checkboxes
  ok: list without a preceding blank line

smoke: all 50 passed
Verdict: PASS
```

```
Command: negctl.sh <worktree> "bash tests/smoke.sh" "sed -i '' 's/+lists_without_preceding_blankline//' bin/spacedown"
Exit: 0
Output:
    FAIL: list folded into the paragraph as literal text
  smoke: 49 passed, 1 FAILED
Restore: git checkout HEAD -- bin/spacedown
Verdict: PASS
```

## Real document

A process playbook with 9 checklist sections, rendered with the pandoc reader: before the flag, 2 lists and 0 checkboxes; with it, 12 lists and 39 checkboxes.

## Note

The Safari drop extension renders through `~/.local/libexec/spacedown-render`, which launches `spacedown-open` from `~/.local/bin`, so the fix reaches Safari on a `git pull` of the checkout, with no app rebuild.
