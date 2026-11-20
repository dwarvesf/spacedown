# intel-slice

The 1.2.0 build is universal (arm64 and x86_64) but every CI job ran on Apple silicon, so nothing ran the x86_64 slice. This adds `tests/intel-slice-test.sh` (every Mach-O in the built app has both slices, the Quick Look extension thins to a real x86_64 Mach-O, the bundled CLI renders under `arch -x86_64`, and `REQUIRE_INTEL=1` fails on a non-Intel host) and an `Intel Mac (x86_64 slice)` CI job on the hosted `macos-26-intel` runner that builds the app, runs that test and runs the smoke suite. Hosted Intel labels today (actions/runner-images README): `macos-26-intel`, `macos-15-intel`; macOS 14 Intel images are retired.

## Green run (local, Apple silicon with Rosetta; the CI run on Intel is in the section below)

```
Command: NO_INSTALL=1 /bin/bash integrations/build-safari.sh
Exit: 0
Output: .../Build/Products/Release/Spacedown.app
Verdict: PASS

Command: /bin/bash tests/intel-slice-test.sh <that Spacedown.app>
Exit: 0
Output: ok   2 Mach-O files, each with arm64 and x86_64
        ok   lipo -thin x86_64 gives an x86_64 Mach-O
        ok   heading page rendered under arch -x86_64
        ok   math typeset with inlined fonts under arch -x86_64
        intel-slice-test: 4 passed, 0 failed
Verdict: PASS
```

## Negative control

```
Command: /bin/bash tests/intel-slice-test.sh <copy of the app>
Exit: 0 (green before the mutation)
Mutation: lipo -thin arm64 on the copy's SpacedownQL executable, copied back over it (an arm64-only build)
Exit: 1 (under the mutation)
Output: FAIL 2 Mach-O files; not universal:
            Contents/PlugIns/SpacedownQL.appex/Contents/MacOS/SpacedownQL: arm64
        FAIL no x86_64 slice in the Quick Look extension executable
        intel-slice-test: 2 passed, 2 failed
Restore: test the untouched app again
Exit: 0 (green after the restore)
Output: intel-slice-test: 4 passed, 0 failed
Verdict: RED, as expected

Command: REQUIRE_INTEL=1 /bin/bash tests/intel-slice-test.sh <app>   (on this arm64 Mac)
Exit: 1
Output: FAIL REQUIRE_INTEL=1 but this host is arm64 (translated=0)
Verdict: RED, as expected: the CI job cannot pass on an Apple silicon runner
```

## Reproduce

```
NO_INSTALL=1 integrations/build-safari.sh --with-safari
bash tests/intel-slice-test.sh <printed Spacedown.app path>
bash scripts/check.sh
```
