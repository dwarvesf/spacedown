# Verification -- katex-pin

spacedown now loads KaTeX from one exact version, `https://cdn.jsdelivr.net/npm/katex@0.19.0/dist/`, on both pandoc paths (`--katex=URL` and `--math-method=katex:URL`). Before, pages loaded `katex@latest`, which floats. 0.19.1 is newer but was under two weeks old on the pin date, so the pin takes 0.19.0.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
Command: bash tests/smoke.sh
Exit: 0
Output:
[katex] the page loads one pinned KaTeX version, never katex@latest
  ok: katex loads from an exact pinned version
smoke: all 128 passed
Verdict: PASS
```

Rendering `tests/fixture/fixture.md` gives 2 references to `katex@0.19.0` and 0 to `katex@latest`; `curl -sI` on the pinned `katex.min.js` returns HTTP 200; a `--shot` of an inline and a display formula shows both typeset (pandoc 3.12.1, `--math-method` path).

## Negative control

```
Command: revert both katex_flag lines to the unpinned flags; bash tests/smoke.sh
Exit: 1
Output:
[katex] the page loads one pinned KaTeX version, never katex@latest
  FAIL: katex pin: page loads katex@latest
smoke: 127 passed, 1 FAILED
Verdict: RED as expected
```

`bin/spacedown` was restored with `git checkout --`, and the suite printed `smoke: all 128 passed` again.

## Not proven

- The `--katex=URL` fallback path ran only through code reading here; this host has pandoc 3.12.1, which takes the `--math-method` path.
- Bumping the version is a manual edit of `KATEX_BASE_URL`.
