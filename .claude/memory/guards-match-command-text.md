---
name: guards-match-command-text
description: The agent hook matches the text of a command, so a script file or a variable hides a command from it; review and CI are the second line.
---

`scripts/agent-guard.sh` is text matching on the command line, not a shell parser. It cannot see `bash -c`, a command built from variables, a script that runs git itself, or a `sed -i` on a frozen file. It also guards Claude Code only. Other agents get no hook at all.

**Why:** the hook is a convenience that names the fix at the moment of the mistake. It is not a wall. The server-side ruleset on `main` and review are the checks that bind.

**How to apply:** do not hide a command from the hook, for example in a variable or a helper script, to get past it. The rule still holds, and a reviewer will find the break later at a higher cost. When the hook blocks you, read the fix it prints and use it. A new guard states its limits in its header.
