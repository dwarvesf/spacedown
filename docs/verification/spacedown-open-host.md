# Verification -- spacedown-open --host

`integrations/spacedown-open --host <ssh-alias> <md>` renders standalone, copies the HTML to `/tmp/review/` on the host, opens it there with the existing browser order, and prints the remote path last. Without `--host` the script behaves as before.

| Check | Result |
|---|---|
| No-flag path, `SPACEDOWN_BROWSER=NoSuchApp`, old script vs new | stdout, stderr, exit 0 identical |
| Live `--host air` on a throwaway md | exit 0, last line `/tmp/review/sdo-test.html`, `ssh air ls` finds it, 7 inline `<style>`, 0 external `<link>`/`<script src>` |
| Remote open with a fish login shell on the host | `bash -s` on stdin; Helium opened (non-existent app skipped) |
| Bad host alias | ssh error, exit 255, no remote path printed |
| tests/smoke.sh | all 149 passed |
| Negative control: old script given `--host` | RED, `unknown flag: --host`, exit 64, no file on the Air |

## Green run
```
Command: integrations/spacedown-open --host air /tmp/sdo-test.md
Exit: 0
Output:
  /tmp/review/sdo-test.html
Command: ssh air 'ls /tmp/review/sdo-test.html'
Output:
  /tmp/review/sdo-test.html
Command: bash tests/smoke.sh
Exit: 0
Output:
  smoke: all 149 passed
Verdict: PASS
```

## Negative control
```
Command: /tmp/spacedown-open.old --host air /tmp/sdo-negctl.md   (pre-change script)
Exit: 64 (RED expected)
Output:
  spacedown: unknown flag: --host (see --help)
Command: ssh air 'ls /tmp/review/sdo-negctl.html'
Output:
  ls: /tmp/review/sdo-negctl.html: No such file or directory
Verdict: PASS (new script green, old script red)
```

## Rollback
- Revert the commit; the change is one shell script plus its README lines.
