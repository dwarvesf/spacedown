# Proof of Done, ia-embed-fonts

On the Air, Safari showed the system font for `ia` pages while Chromium on the Mini showed iA Writer Quattro. Safari only lets pages use fonts that ship with macOS, so an installed iA font is ignored. Themes that name the iA fonts now embed the four vendored faces as data URIs (`scripts/ia-fontface-css`, shared with the Quick Look skin build). `SPACEDOWN_EMBED_FONTS=0` opts out.

**Date:** 2026-10-16 · **Lane:** normal · **Host:** Mac-mini-2 · **Branch:** `fix/ia-embed-fonts`

## Green run

```
Command: bash tests/smoke.sh
Exit: 0
Output:
[fonts] the ia page embeds the iA fonts (Safari ignores installed ones); tm and the opt-out do not
  ok: 4 embedded faces in ia, none with SPACEDOWN_EMBED_FONTS=0 or tm
smoke: all 60 passed
Verdict: PASS
```

```
Command: negctl.sh <worktree> "bash tests/smoke.sh" "sed ... SPACEDOWN_EMBED_FONTS:-1 -> :-0 in bin/spacedown"
Exit: 0
Output:
Exit: 0 (green before mutation)
  smoke: all 60 passed
Exit: 1 (under mutation, RED expected)
  [fonts] the ia page embeds the iA fonts (Safari ignores installed ones); tm and the opt-out do not
Restore: git checkout HEAD -- bin/spacedown
Exit: 0 (green after restore)
Verdict: PASS
```

## Cost

An `ia` page grows by about 600 KB (a one-paragraph page renders at about 860 KB). Local previews only; `SPACEDOWN_EMBED_FONTS=0` restores the small page.

## Rollback

Revert this squash commit; pages then reference the fonts by name only, as before.
