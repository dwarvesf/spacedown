# Proof of Done, docx-subcommand

`bin/spacedown-docx` is folded into the one CLI as `spacedown docx <file.md> [-o out.docx]`, and the separate script is removed. Plain `spacedown <file>` renders HTML exactly as before. The `docx` word is only a subcommand as the first argument; a file named `docx` renders with `spacedown ./docx`. This is the first step toward shipping one `spacedown` binary inside the app bundle.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |
| `bin/spacedown docx --help` | 0 | PASS |

```
[43] spacedown docx writes a .docx next to the input in the iA look
  ok: iA docx styles (IBM Plex Sans, ink 1A1A1A)
[46] a symlinked spacedown docx still finds the reference doc
  ok: symlink
[docx-1] spacedown docx --help prints usage on stdout and exits 0
[docx-4] plain spacedown <file> still renders HTML, not a docx
  ok: html render unchanged
smoke: all 78 passed
```

## Negative control

The previous `bin/spacedown` (no `docx` dispatch) restored over the new one, same suite:

```
  FAIL: docx is missing the iA styles
  FAIL: -o ignored or the HTML comment leaked
  FAIL: symlink lost the reference doc
smoke: 71 passed, 7 FAILED
```

## Rollback

Revert this squash commit. It restores `bin/spacedown-docx`. A `~/.local/bin/spacedown-docx` link into the repo dangles between the merge and any relink.
