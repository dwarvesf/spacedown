# Proof of Done, consolelabs-urls

The repo moved to `consolelabs/spacedown`. Every live repo URL now names consolelabs. The only source change is the `REPO` default in `scripts/release.sh` (a string; no logic changed). The Homebrew tap install string stays as is.

## Green run

```
Command: rg -c 'dwarvesf/spacedown' --glob '!docs/verification/**' --glob '!build/**' --hidden --glob '!.git'
Exit: 1
Output: (no matches)
Verdict: PASS
```

```
Command: bash -n scripts/release.sh && rg -n '^REPO=' scripts/release.sh
Exit: 0
Output: 54:REPO="${REPO:-consolelabs/spacedown}"
Verdict: PASS
```

```
Command: rg -c 'dwarvesf/tools/spacedown' README.md site/index.html integrations/safari/SpacedownDrop/SpacedownDrop/Onboarding.swift
Exit: 0
Output:
README.md:1
site/index.html:2
integrations/safari/SpacedownDrop/SpacedownDrop/Onboarding.swift:1
Verdict: PASS (tap strings intact)
```

```
Command: curl -s -o /dev/null -w "%{http_code}" <url>
Exit: 0
Output:
302 https://github.com/consolelabs/spacedown/releases/latest
200 https://github.com/consolelabs/spacedown/issues
200 https://github.com/consolelabs/spacedown/blob/main/docs/PRIVACY.md
Verdict: PASS
```

## Reproduce

Run the commands above from the repo root.
