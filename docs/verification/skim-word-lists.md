# Proof of Done, skim-word-lists

Skim's two word-frequency lists were replaced, because the sources of the old ones did not allow commercial use (one forbids commercial use of its corpus data without an LDC license, the other is for research and teaching only). Both lists are now derived by `scripts/skim-lists.mjs` from public-domain texts named in `scripts/skim-lists/sources.tsv`: 57 English works and 13 Chinese works from Project Gutenberg, each by contributors who all died in 1955 or earlier and first published in 1929 or earlier, with the Chinese folded from Traditional to Simplified through Unihan 16.0.0 (Unicode License V3, build time only). Format, sizes and engine code are unchanged: 3000 space-separated English keys, 2000 BMP Han characters. The Skim goldens were regenerated against upstream skimgram `4ebb78a` fed the same new lists, so parity still means "the port scores exactly like skimgram". `scripts/skim-parity.mjs` now also fails when a source in the manifest is not credited in `THIRD_PARTY_NOTICES.md`, which puts that check inside the smoke parity section CI already runs.

## Green run

```
Command: node scripts/skim-lists.mjs build --cache <dir> --record-hashes --write
Exit: 0
Output: EN_WORDS  3000 words from 57 works, sha256 5161396b...0992a6e5
        CJK_CHARS 2000 characters from 13 works, sha256 fc612b51...62f555dd
        wrote both lists to assets/skim-surprise.html
Verdict: PASS
```

```
Command: node scripts/skim-lists.mjs build --cache <dir>        (a second build from the same files, no write)
Exit: 0
Output: skim-lists: the engine's lists equal the rebuild
Verdict: PASS, the build is byte-reproducible
```

```
Command: node scripts/skim-parity.mjs --upstream <skimgram clone at 4ebb78a> --cache <dir> --write-golden
Exit: 0
Output: wrote 11 goldens and _meta.json to tests/fixtures/skim/golden
        word list EN_WORDS 3000 entries same as upstream
        word list CJK_CHARS 2000 entries same as upstream
        word list sources 71 in scripts/skim-lists/sources.tsv all credited in THIRD_PARTY_NOTICES.md
        0 mismatched tokens over 11 fixtures, 0 flatten differences, 0 word list differences, 0 token count differences
        skim-parity: OK
Verdict: PASS, max score difference 0 on every fixture
```

```
Command: /bin/bash tests/smoke.sh
Exit: 0
Output: smoke: all 192 passed
Verdict: PASS
```

```
Command: /bin/bash tests/katex-one-test.sh; /bin/bash tests/size-budget-test.sh; node tests/hljs-bundle-test.js
Exit: 0
Output: katex-one-test: 9 passed, 0 failed
        size-budget-test: 5 passed, 0 failed
        hljs-bundle-test: all passed
Verdict: PASS
```

## Negative control

```
Command: node scripts/skim-parity.mjs ; /bin/bash tests/smoke.sh --only parity
Exit: 0 (green before the mutation)
Mutation: delete "#1342 Pride and Prejudice (Jane Austen); " from THIRD_PARTY_NOTICES.md
Exit: 1 (skim-parity), 1 (smoke)
Output: THIRD_PARTY_NOTICES.md does not credit en source #1342 (Pride and Prejudice)
        word list sources 71 in scripts/skim-lists/sources.tsv NOT all credited in THIRD_PARTY_NOTICES.md
        0 mismatched tokens over 11 fixtures, 0 flatten differences, 1 word list differences, 0 token count differences
        skim-parity: FAIL
        FAIL: the port differs from the skimgram goldens
        smoke: 1 passed, 1 FAILED
Restore: copy the saved THIRD_PARTY_NOTICES.md back
Exit: 0 (green after the restore: skim-parity: OK, smoke: all 2 passed)
Verdict: RED, as expected
```

## Skim output before and after

Same engine, old lists against new lists, default settings (intensity 50, basis auto). "In list" is the share of scored tokens found in a list; "level changed" is the share of scored tokens whose Skim level (-2 to 2) differs. No token moved two levels or more on any sample.

| Sample | Scored tokens | In list, old | In list, new | Level changed | Bright words kept |
|---|---|---|---|---|---|
| `README.md` (modern technical English) | 3430 | 65.7% | 52.2% | 2.2% | 299 of 304 |
| `docs/dev/testing.md` | 871 | 64.4% | 51.3% | 4.6% | 77 of 81 |
| `docs/dev/development.md` | 592 | 58.3% | 44.1% | 5.4% | 62 of 64 |
| first 3000 bytes of `CONTRIBUTING.md` | 444 | 62.4% | 45.5% | 4.5% | 41 of 43 |
| first 1600 bytes of `docs/dev/testing.md` (short page, surprisal basis) | 228 | 51.3% | 43.0% | 4.4% | 26 of 26 |
| first 1600 bytes of `docs/dev/development.md` (short page, surprisal basis) | 150 | 61.3% | 46.7% | 0.0% | 17 of 17 |
| `tests/fixtures/skim/en-long.txt` (Alice) | 5340 | 81.8% | 89.0% | 2.9% | 386 of 398 |
| `tests/fixtures/skim/en-short.txt` | 363 | 80.4% | 88.7% | 2.8% | 41 of 41 |
| `tests/fixtures/skim/identifiers.txt` | 358 | 31.0% | 26.5% | 0.8% | 8 of 8 |
| `tests/fixtures/skim/cjk.txt` (modern Simplified Chinese) | 918 | 98.1% | 95.4% | 8.3% | 72 of 86 |

What moved: the new English list is literary (1478 of 3000 words are shared with the old one). Prose and fiction are covered better; modern technical words (`software`, `file`, `data`, `code`, `online`) are no longer in it, so on technical docs about 5% of words shift one level (as many up as down, since levels are ranks within the page). The language rule still picks the English prior on every sample, but the margin on technical pages is smaller (43% to 52% of words in the list against the 35% floor, which only applies when 5% or more of the words carry non-ASCII letters). The Chinese list shares 1678 of 2000 characters with the old one; vernacular-novel characters rank higher (`道` 11 against 52, `曰` 125 against 1656) and `们` lower (36 against 13). Traditional forms with two Simplified readings fold to the first one, so `着` is in (25) and `著` is out (it was 777). No fixture changed language, basis or skip reason.

## Reproduce

```bash
node scripts/skim-lists.mjs check-notices          # offline provenance check
node scripts/skim-lists.mjs build                  # rebuild from the sources, compare with the engine
node scripts/skim-parity.mjs                       # port against the committed goldens, plus the provenance check
node scripts/skim-parity.mjs --upstream <skimgram clone at 4ebb78a>   # against upstream with the rebuilt lists
/bin/bash tests/smoke.sh
```
