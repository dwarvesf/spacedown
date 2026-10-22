# Proof of Done, table-under-text

A pipe table right under a line of text (`**Performance**` then `| Date | ... |`) rendered as literal pipes, because pandoc's markdown reader needs a blank line before a table. GitHub, Obsidian and the Quick Look appex render it as a table. `assets/tables-blankline.py` now inserts that blank line before pandoc runs, and leaves code fences alone.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
[table] a table right under a line of text is a table; a fenced one stays code
  ok: table without a preceding blank line
smoke: all 122 passed
```

Real file, `family-office/assets/private-investments.md`: the body has 3 `<th>Date</th>` headers and no literal `| Date |` line.

## Negative control

`render_tables` removed from the render pipeline in `bin/spacedown`, same check:

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh \| grep -q 'ok: table without a preceding blank line'` (mutated) | 1 | RED, as expected |
| same, after `git checkout HEAD -- bin/spacedown` | 0 | GREEN |

## Reproduce

`bash tests/smoke.sh`, then look for the `[table]` block.

## docx path

`spacedown docx` read the source straight into pandoc and showed the same bug. It now runs the same pre-pass.

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |
| `bash tests/smoke.sh \| grep -q 'ok: docx table without a preceding blank line'` (old `bin/spacedown` from origin/main) | 1 | RED, as expected |
| same, after `git checkout HEAD -- bin/spacedown` | 0 | GREEN |

```
[docx-table] a table right under a line of text is a Word table
  ok: docx table without a preceding blank line
smoke: all 123 passed
```
