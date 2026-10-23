# Proof of Done, shot-flag

`spacedown <file.md> --shot <png>` renders, then screenshots the output in a private headless browser and warns about tables that scroll sideways. The browser is found like `scripts/layout-check` does: `BROWSER`, else Helium, then Chrome and Chromium. Never Edge. Every launch gets a fresh `--user-data-dir`.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
[--shot] argument errors
  ok: --shot with --watch, a directory or a bad width exits 64
[--shot] screenshot and wide-table warning
  ok: --shot writes a non-empty PNG, prints its path, no warning on a narrow table
  ok: a very wide table prints a WARN wide table line

smoke: all 127 passed
```

## Negative control

The wide fixture first used 14 columns. That table fit the 1300px page (1180px table in a 1206px container), so no warning fired and the assertion failed:

```
  FAIL: --shot wide: rc=0 out=... shot-wide.png
smoke: 126 passed, 1 FAILED
```

Widening the fixture to 30 columns made the table overflow, the `WARN wide table` line printed and the suite went green. Narrow fixture: no warning, as asserted.

## Rollback

Revert the `--shot` commits. Nothing else reads the flag.
