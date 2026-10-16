# Proof of Done, phone-table-scroll

`scripts/layout-check` found the fixture's six-column numeric table 4px wider than a 390px phone column, so the whole page scrolled sideways. On phones (600px and below) a body table now scrolls inside its own box. The frontmatter table is excluded; it already wraps.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |
| `scripts/layout-check --widths 390,1470 tests/fixture/fixture.md` | 0 | PASS |

```
[phone-table] on phones a wide table scrolls in its own box
  ok: phone table scroll
smoke: all 95 passed

W=390 viewport=392 scroll=392 overflow=no content=20-372 gapLeft=20 gapRight=20 edges=372
W=1470 viewport=1462 scroll=1462 overflow=no content=318-1398 gapLeft=78 gapRight=64 edges=1398
```

The WALA #5 article gives the same clean lines at both widths.

## Negative control

The prior `assets/reading-chrome-head.html` restored over the fix:

```
  FAIL: phone table scroll missing: a wide table pushes the page sideways on a phone
smoke: 94 passed, 1 FAILED
W=390 viewport=392 scroll=396 overflow=yes content=20-396 gapLeft=20 gapRight=-4 edges=372/396
```

## Rollback

Revert this squash commit.
