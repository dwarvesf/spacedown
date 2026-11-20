# Proof of Done, skim-tech-vocab

The literature-only English list from `skim-word-lists` dropped common technical words (`file`, `data`, `code`). On technical Markdown, Spacedown's main input, it covered only 43 to 52% of words. The English list now blends in a second corpus: the Markdown documentation of seven US federal government repositories, public domain in the US (17 U.S.C. 105) and CC0 worldwide, each pinned to a git revision. The blend is weighted 0.7 literary to 0.3 technical, and the technical works count as one work per agency. Separately, every Project Gutenberg work's publication year is now confirmed by a cited record: a Library of Congress catalog LCCN, or the dated title page in the hashed file. Two Chinese works with neither were dropped. `check-notices` (run by `skim-parity`, so by smoke and CI) now also fails a source with no evidence.

## Coverage

Share of scored words found in `EN_WORDS`, default Skim settings. "Old" is the list Skim shipped before #95 (`git show 2433a85:assets/skim-surprise.html`), "main" is the literature-only list from #95, and "new" is this PR.

| Sample | Kind | Old | Main | New |
|---|---|---|---|---|
| `README.md` | technical | 65.7% | 52.2% | 66.1% |
| `docs/dev/testing.md` | technical | 65.9% | 52.5% | 68.3% |
| `docs/dev/development.md` | technical | 58.3% | 44.1% | 60.3% |
| first 3000 bytes of `CONTRIBUTING.md` | technical | 62.4% | 45.5% | 64.0% |
| first 1600 bytes of `docs/dev/testing.md` (surprisal basis) | technical | 51.3% | 43.0% | 57.0% |
| first 1600 bytes of `docs/dev/development.md` (surprisal basis) | technical | 61.3% | 46.7% | 59.3% |
| `tests/fixtures/skim/code-mixed.txt` | technical | 65.3% | 56.2% | 71.0% |
| `tests/fixtures/skim/en-long.txt` (Alice) | fiction | 81.8% | 89.0% | 87.2% |
| `tests/fixtures/skim/en-short.txt` | fiction | 80.4% | 88.7% | 86.8% |
| `tests/fixtures/skim/cjk.txt` | Chinese | 98.1% | 95.4% | 95.5% |

Against main, Skim levels change on 0 to 3% of scored words, none by two levels or more. Technical docs are back at or above the old level on six of seven samples; the seventh is a 150-token page, 2 points under. Fiction is 2 points under main and 5 to 6 over the old list.

## Weight sweep

Technical weight (literary weight is 1 minus it), measured with the same samples:

| Tech weight | README | testing.md | development.md | CONTRIBUTING head | testing head | development head | Alice long | Alice short | Rank of `file` / `data` / `code` / `api` / `gov` / `18f` |
|---|---|---|---|---|---|---|---|---|---|
| 0.2 | 63.8% | 65.8% | 58.4% | 60.8% | 55.3% | 56.7% | 87.7% | 88.2% | 359 / 92 / 172 / 353 / 561 / 645 |
| **0.3** | 66.1% | 68.3% | 60.3% | 64.0% | 57.0% | 59.3% | 87.2% | 86.8% | 255 / 64 / 114 / 248 / 403 / 462 |
| 0.4 | 69.2% | 74.1% | 67.4% | 68.9% | 66.2% | 68.0% | 86.5% | 86.2% | 199 / 55 / 87 / 188 / 309 / 368 |
| 0.5 | 70.4% | 75.1% | 67.4% | 69.8% | 68.4% | 68.7% | 85.8% | 85.7% | 164 / 41 / 77 / 158 / 260 / 305 |

0.3 is the smallest weight that reaches the old technical level; higher weights trade fiction coverage for agency jargon (`gov`, `18f`) ranking higher. The old list ranked `file` 281, `data` 131, `code` 267.

## Green run

```
Command: node scripts/skim-lists.mjs build --cache <dir> --write
Exit: 0
Output: EN_WORDS  3000 words from 57 literary works and 7 technical repositories (2 agencies), sha256 b49d7b18...b2ea491f
        CJK_CHARS 2000 characters from 11 works, sha256 06865c6c...f0d1824b81
        wrote both lists to assets/skim-surprise.html
Verdict: PASS
```

```
Command: node scripts/skim-lists.mjs build --cache <new empty dir>     (cold: every file and repository fetched again)
Exit: 0
Output: EN_WORDS  3000 words from 57 literary works and 7 technical repositories (2 agencies), sha256 b49d7b18...b2ea491f
        CJK_CHARS 2000 characters from 11 works, sha256 06865c6c...f0d1824b81
        skim-lists: the engine's lists equal the rebuild
Verdict: PASS: no sha256 drift, every repository at its pinned revision, rebuild byte-identical
```

```
Command: node scripts/skim-parity.mjs --upstream <skimgram clone at 4ebb78a> --cache <dir> --write-golden
Exit: 0
Output: word list EN_WORDS 3000 entries same as upstream
        word list CJK_CHARS 2000 entries same as upstream
        word list sources 76 in scripts/skim-lists/sources.tsv all credited in THIRD_PARTY_NOTICES.md
        0 mismatched tokens over 11 fixtures, 0 flatten differences, 0 word list differences, 0 token count differences
        skim-parity: OK
Verdict: PASS, goldens regenerated; parity-2's boundary checks (gain switch, skip reasons, cap) still pass
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
Mutation: empty the evidence cell of #1342 in scripts/skim-lists/sources.tsv
Exit: 1 (skim-parity), 1 (smoke)
Output: #1342 has no evidence (publication record or license) in the manifest
        0 mismatched tokens over 11 fixtures, 0 flatten differences, 1 word list differences, 0 token count differences
        skim-parity: FAIL
        FAIL: the port differs from the skimgram goldens
        smoke: 1 passed, 1 FAILED
Restore: copy the saved sources.tsv back
Exit: 0 (green after the restore: skim-parity: OK, smoke: all 2 passed)
Verdict: RED, as expected
```

```
Command: node scripts/skim-parity.mjs
Exit: 0 (green before the mutation)
Mutation: rename the `CMSgov/beneficiary-fhir-data` credit in THIRD_PARTY_NOTICES.md to `CMSgov`
Exit: 1
Output: THIRD_PARTY_NOTICES.md does not credit en source CMSgov/beneficiary-fhir-data (Beneficiary FHIR Data Server (Blue Button) documentation)
        skim-parity: FAIL
Restore: copy the saved THIRD_PARTY_NOTICES.md back
Exit: 0 (skim-parity: OK)
Verdict: RED, as expected
```

## Publication years

Every Gutenberg row's `evidence` cell in `scripts/skim-lists/sources.tsv` cites a Library of Congress catalog record (LCCN, plain imprint date, title and author checked) or the dated title page in the hashed file. Dropped for want of either: 野草 (#25242) and 文明小史 (#25379).

## Reproduce

```bash
node scripts/skim-lists.mjs check-notices
node scripts/skim-lists.mjs build --cache <empty dir>   # cold: fetches every source, git included
node scripts/skim-parity.mjs
/bin/bash tests/smoke.sh
```
