---
name: bash-32-heredoc-in-subshell
description: macOS /bin/bash is 3.2, CI runs the suite with it, and 3.2 misparses a heredoc inside $( ); write the heredoc to a temp file first.
---

Test and build scripts run under `/bin/bash` 3.2 on a Mac and in CI. Bash 3.2 has no associative arrays, no `mapfile`, no `${var,,}`, and it misparses a heredoc inside `$( )`.

**Why:** a script that passes under Homebrew bash 5 can fail only in CI, and the failure looks like a syntax error far from the heredoc. CI runs `/bin/bash -n` on every `tests/*.sh`.

**How to apply:** write the heredoc to a `mktemp` file and read it back. Run your script with `/bin/bash`, not `bash`, before you push. `bash scripts/check.sh` does both the syntax check and the suite under `/bin/bash`. Detail: `docs/dev/testing.md`, section "bash 3.2".
