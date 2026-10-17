# Proof of Done, katex-flag

`bin/spacedown` passed `--katex` to pandoc. Pandoc 3.11 deprecated that flag, so every render printed `[WARNING] Deprecated: --katex. Use --math-method=katex[:URL] instead.` The CLI now uses `--math-method=katex` (no URL, so pandoc keeps its default KaTeX URL) when `pandoc --help` lists `--math-method`, and keeps `--katex` otherwise.

Version finding: `--syntax-highlighting` arrived in pandoc 3.8, which is the floor the script already needed. `--math-method` arrived in pandoc 3.11. Switching unconditionally would have raised the floor from 3.8 to 3.11, so the flag is detected, not assumed. Pandoc 3.8 to 3.10 keep `--katex`.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
[10b] render stderr has no Deprecated warning
  ok: no Deprecated warning on stderr
smoke: all 111 passed
```

## Output diff

Same input rendered by `origin/main` `bin/spacedown` (`--katex`) and by this branch (`--math-method=katex`), pandoc 3.11, `cmp` on the HTML.

| Input | Old stderr "Deprecated" lines | New stderr "Deprecated" lines | HTML |
|---|---|---|---|
| inline and display math plus a code block | 1 | 0 | byte-identical (959618 B) |
| `tests/fixture/fixture.md` | 1 | 0 | byte-identical (976638 B) |

Both pages still load `https://cdn.jsdelivr.net/npm/katex@latest/dist/katex.min.js`, so the default URL is unchanged.

## Fallback

A `pandoc` shim that hides `--math-method` from `--help` and rejects the flag, put first on `PATH`:

| Check | Result |
|---|---|
| render exits | 0 |
| HTML vs the new-path render | byte-identical |

The shim run falls back to `--katex`. The one "Deprecated" line there comes from real pandoc 3.11 receiving `--katex`, which is expected on that path.

## Negative control

Fix committed first. Then the detected flag forced back to `--katex`, same suite:

```
  FAIL: pandoc deprecation warning: [WARNING] Deprecated: --katex. Use --math-method=katex[:URL] instead.
smoke: 110 passed, 1 FAILED
```

Restored with `git checkout -- bin/spacedown`, suite re-run:

```
smoke: all 111 passed
```

## Rollback

Revert the fix commit. Renders return to `--katex` and the warning on pandoc 3.11 or newer.
