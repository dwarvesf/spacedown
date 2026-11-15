# Proof of Done, r1-pandoc-drift

Docs and code comments only. After #71 the CLI renders HTML through the Quick Look JavaScript core and pandoc is needed only by `spacedown docx`. The lines that still said pandoc renders HTML are fixed in `THIRD_PARTY_NOTICES.md`, `integrations/README.md`, `spacedown-render.swift` and `SafariWebExtensionHandler.swift`. `README.md` needs nothing more: #71 already fixed its lines. No file is deleted.

## Green run

```
Command: swiftc -parse integrations/safari/helper/spacedown-render.swift
Exit: 0
Command: swiftc -parse "integrations/safari/SpacedownDrop/SpacedownDrop Extension/SafariWebExtensionHandler.swift"
Exit: 0
Command: git diff origin/main -- '*.swift' | grep '^[-+][^-+]' | grep -cv '^[-+]\s*//'
Output: 0   (no Swift line other than a comment changed)
Command: rg -n -i pandoc THIRD_PARTY_NOTICES.md integrations/README.md <the two Swift files>
Output:
THIRD_PARTY_NOTICES.md:29:| pandoc | Optional, `.docx` export in the CLI (`spacedown docx`); HTML needs no pandoc | GPL-2.0-or-later | https://github.com/jgm/pandoc |
THIRD_PARTY_NOTICES.md:32:The spacedown CLI runs pandoc and entr as separate programs and includes none of their code.
Verdict: PASS (both remaining lines are true: docx still runs pandoc)
```

## Order

Merge after #71. On main before #71 these lines are still true.
