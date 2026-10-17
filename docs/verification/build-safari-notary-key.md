# Proof of Done, build-safari-notary-key

`integrations/build-safari.sh` can now notarize with an App Store Connect API key, the way `scripts/release.sh` does. `NOTARY_KEY` (a `.p8` path) with `NOTARY_KEY_ID` and `NOTARY_ISSUER` gives `--key/--key-id/--issuer`; a missing id or issuer fails before the build starts. Without `NOTARY_KEY` the `NOTARIZE` keychain profile path is unchanged. Either variable triggers notarization, with the same Developer ID `SIGN_ID` precondition. The choice lives in the sourced `integrations/notary-auth.sh` so the smoke test can run it without Xcode. Nothing was built, notarized, pushed or released.

## Green run

```
Command: bash tests/smoke.sh
Exit: 0
Output:
  [notary-auth] NOTARY_KEY selects the API key; else the keychain profile
    ok: NOTARY_KEY gives --key/--key-id/--issuer, ahead of NOTARIZE
    ok: NOTARY_KEY unset gives --keychain-profile <name>
    ok: NOTARY_KEY without NOTARY_KEY_ID or NOTARY_ISSUER fails before xcrun runs
    ok: build-safari.sh notarizes on either variable through NOTARY_AUTH
  [layout-check] usage and argument errors need no browser
    ok: --help exits 0; no file and unknown option exit 64
  
  smoke: all 121 passed
Verdict: PASS
```

The checks put a fake `xcrun` on `PATH` that records its argv and pass it `"${NOTARY_AUTH[@]}"`, so the recorded line is exactly what notarytool would receive.

Not verified here: a real notarization with an API key. That needs the Developer ID identity and the key.

## Negative control

`integrations/notary-auth.sh` with `--key "$NOTARY_KEY"` rewritten to `--keychain-profile "$NOTARY_KEY"`, same suite, run through `negctl.sh`:

```
Mutation: sed -i '' 's/--key "$NOTARY_KEY"/--keychain-profile "$NOTARY_KEY"/' integrations/notary-auth.sh
Changed: integrations/notary-auth.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL: api key argv: notarytool submit z.zip --keychain-profile /k/AuthKey.p8 --key-id KID --issuer ISS --wait
  smoke: 120 passed, 1 FAILED
Restore: git checkout HEAD -- integrations/notary-auth.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert this commit; `build-safari.sh` goes back to the keychain profile only and `integrations/notary-auth.sh` is removed.
