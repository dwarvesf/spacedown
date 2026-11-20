# Proof of done: landing page pricing matches the license decision

The landing page advertised a price, a 14-day trial, four named Pro features and "App Store or license key". README and [ADR 0001](../decisions/0001-agpl-and-paid-feature-gate.md) say the viewer is free with no trial and that no paid feature or price is decided. The Pro section and the pricing cards are replaced by one short block, "Free, open source. A Pro upgrade is coming.", and the two FAQ answers about a trial and an account for Pro are replaced. The rest of the page is unchanged. This is a static page: no test covers it, so the proof is a text check plus before and after renders.

## Green run

```
Command: rg -c -i "19 USD|free trial|license key|Since-last-read|Agent inbox|Read aloud" site/index.html
Exit: 1 (no match)
Output: (empty)
Verdict: PASS
```

```
Command: rg -n -i "pro upgrade" site/index.html
Exit: 0
Output:
184:<h2 class="h2">Free, open source. A Pro upgrade is coming.</h2>
225:<p>Yes. The code is open source under the AGPL-3.0, at github.com/consolelabs/spacedown. Releases up to v1.1.0 stay MIT. A Pro upgrade is coming.</p>
Verdict: PASS
```

## Negative control

The same check against the page before the change must find the old claims.

```
Command: git show HEAD:site/index.html | rg -c -i "19 USD|free trial|license key|Since-last-read"
Exit: 0 (matches before the change)
Output: 6
Verdict: RED before, as expected
```

## Screenshots

Headless browser render of `site/index.html` at 1280 pixels wide, no app launched. The Pro section and the pricing cards sit above "Give your agents eyes".

- Before: [before.png](site-pricing/before.png)
- After: [after.png](site-pricing/after.png)

## Reproduce

```
rg -c -i "19 USD|free trial|license key" site/index.html
git show HEAD:site/index.html | rg -c -i "19 USD|free trial|license key"
```

Open `site/index.html` in a browser and scroll to the Pricing block.
