# Proof of done: landing pages tracked

PR #67 merged the site without its two HTML pages, because `.gitignore` ignores `*.html`. This adds a `!site/*.html` exception and restores `site/index.html` and `site/privacy.html` from the node worktree.

```
Command: tools/interactive-concept-board/bin/verify --shots <tmp> site/index.html site/privacy.html
Exit: 0
Output:
WARN  index    self-test no self-test  console-errors 0   moved n/a  overflow no
WARN  privacy  self-test no self-test  console-errors 0   moved n/a  overflow no
0 pass, 2 warn, 0 fail
Verdict: PASS
```

Every `assets/` path referenced by index.html exists under site/. The two WARN lines are the tool noting static pages have no self-test.
