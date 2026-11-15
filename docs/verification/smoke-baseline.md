# Proof of Done, smoke-baseline

Two changes to `tests/`: the flaky Skim settings check is made deterministic, and `tests/smoke.sh` can run part of the suite. No product code changed.

## Root cause

`bash tests/smoke.sh` on main 286ef79 once reported `FAIL: Skim settings panel or its persistence wrong` (1 of 149). The product was right and the test was wrong.

The check ends with `r["settings"]["off"]["restored"]`: after Skim is turned Off, `sig()` must equal the `sig()` taken at page start. `sig()` hashes the `innerHTML` of every `p, li, td, th, blockquote, h1, h2, h3`, which includes the outline (`nav#TOC li`). The outline scroll-spy (`assets/reading-chrome-foot.html`, an `IntersectionObserver`) adds `class="sd-active"` to the link of the section in view, and the observer reports its first entry a few frames after load. On a quiet machine that lands before the driver's baseline (300 ms after load); on a loaded machine it lands after, so the baseline lacks `sd-active` and the end state has it.

Evidence:

| Check | Result |
|---|---|
| `bash tests/smoke.sh` on unmodified main code, quiet machine, 65 s | 149 of 149, the failure does not reproduce |
| the Skim settings checks alone, 3 runs | all pass |
| 24 and 32 parallel drives of `reading-en` with 28 CPU burners | 2 of 24 and 2 of 32 failed, only `off.restored` false, `left` all 0 |
| the same drive with the driver logging the first differing line | `<a href="#reading-modes" id="toc-reading-modes">` vs the same tag plus `class="sd-active"`, in all failures |

Fix: `sig()` drops the one `class="sd-active"` marker before comparing. Everything else, including the rest of the outline, still has to restore byte for byte.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/smoke.sh` | 0 | PASS |

```
Command: bash tests/smoke.sh
Exit: 0
Output: smoke: all 149 passed
Verdict: PASS
```

```
Command: bash tests/smoke.sh --only docx,parity
Exit: 0
Output: smoke: all 12 passed
Verdict: PASS
```

Per section, run alone with `--only` (counts sum to 149):

| Section | Passed | Seconds |
|---|---|---|
| cli | 28 | 9 |
| chrome | 24 | 9 |
| quicklook | 1 | 0 |
| render | 21 | 5 |
| fonts | 2 | 0 |
| docx | 10 | 1 |
| polish | 7 | 2 |
| skim | 6 | 1 |
| reading | 21 | 22 |
| parity | 2 | 0 |
| bundle | 6 | 2 |
| notary | 4 | 0 |
| layout | 1 | 0 |
| shot | 9 | 21 |
| katex | 7 | 2 |

Running `bundle` alone first failed (`bundled docx failed`): it reuses the docx input and `docx_styles` helper that the docx section defined. Both moved to the shared setup at the top, and `bundle` then passes alone.

## Negative control

The flake: the original driver against the fixed one, the same drive of `reading-en` 48 times in parallel with 28 CPU burners.

| Driver | Failed | Passed |
|---|---|---|
| original (`sig()` keeps `sd-active`) | 8 | 40 |
| fixed | 0 | 48 |

The subset flag:

| Command | Exit | Output |
|---|---|---|
| `bash tests/smoke.sh --only nope` | 64 | `smoke: unknown section 'nope' (valid: cli chrome ...)` |
| `bash tests/smoke.sh --only cli,bogus` | 64 | `smoke: unknown section 'bogus' (valid: ...)` |
| `bash tests/smoke.sh --only` | 64 | `smoke: --only needs a section list (see --list)` |
| `bash tests/smoke.sh --only ''` | 64 | `smoke: --only needs at least one section (valid: ...)` |
| `bash tests/smoke.sh --bogus` | 64 | `smoke: unknown option '--bogus' (use --list, --only <section>[,<section>])` |
| `bash tests/smoke.sh --list` | 0 | the fifteen section names, one per line |
