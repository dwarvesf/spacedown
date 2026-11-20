# Repo lessons

Each line is one lesson that cost time once. Read the note before you do the work it covers. Add a note in the PR that paid for it: `AGENTS.md`, section "Lessons".

- [bash 3.2 misparses a heredoc in $( )](bash-32-heredoc-in-subshell.md): macOS `/bin/bash` is 3.2 and CI uses it; write the heredoc to a temp file first, and avoid `mapfile` and associative arrays.
- [The Finder panel runs no scripts](panel-runs-no-scripts.md): the Quick Look preview is HTML with JavaScript off; a feature that needs a key event or a script cannot work there, so build it at render time with CSS.
- [build-safari.sh installs unless NO_INSTALL=1](build-safari-installs-by-default.md): without the flag it installs and registers the app on the Mac you work on; use the flag, and check the live panel in a VM or a clean user.
- [Guards match command text](guards-match-command-text.md): the agent hook sees command text only; do not hide a command from it, review and CI are the second line.
