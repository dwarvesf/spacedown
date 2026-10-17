# Proof of Done, skim-dim-default

Skim now opens with Dim only. skimgram ships Dim and Heat; on real documents that put a bold red box on about 40% of the words and made pages hard to read. Heat and Underline stay in the settings panel. Scoring is untouched. See deviation 3 in `skim-parity.md`.

| Change | Where it lives |
|---|---|
| Default emphasis `["dim"]` instead of `["dim", "heat"]` | `assets/reading-chrome-foot.html` (`var sk`) |
| Migration: a stored `dim,heat` with no `sd-skim-ver` is the old default and is ignored; saving writes `sd-skim-ver` = 2 | same file, settings load and `saveSkim` |
| README and parity record state the new default | `README.md`, `docs/verification/skim-parity.md` |
| Checks: default is Dim, Heat paints when clicked, migration, deliberate mixes kept | `tests/smoke.sh` (`read-9`, `read-10b`, `read-10c`, new `read-10d`), `tests/reading-modes-driver.js` |

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS, 116 checks (115 before) |
| `node scripts/skim-parity.mjs` | 0 | PASS, 0 mismatched tokens over 11 fixtures, goldens unchanged |

## Migration

| Saved before load | Opens as | Why |
|---|---|---|
| nothing | `dim` | new default |
| `dim,heat`, no `sd-skim-ver` | `dim` | the old default, not a choice; intensity and score basis are kept |
| `dim,heat` with `sd-skim-ver` = 2 | `dim heat` | picked after the change, so it is a choice |
| `underline`, or any other mix | as saved | not the old default |

Limit: someone who deliberately chose Dim and Heat before this change cannot be told apart from the old default and gets Dim. One click on Heat brings it back and it then sticks.

## Negative control

Each break was made after the commit and restored with `git checkout --`; the suite was then re-run green.

| Break | Result |
|---|---|
| default line back to `["dim", "heat"]` | `smoke: 112 passed, 4 FAILED` (`read-9`, `read-10b`, `read-10c`, `read-10d`) |
| migration line removed | `smoke: 115 passed, 1 FAILED` (`read-10d`) |

After restore: `smoke: all 116 passed`.

## Reproduce

```bash
bash tests/smoke.sh
node scripts/skim-parity.mjs
```

## Rollback

Revert the commits of this branch. Saved `sd-skim-emph` values stay valid; `sd-skim-ver` is ignored by the old chrome.
