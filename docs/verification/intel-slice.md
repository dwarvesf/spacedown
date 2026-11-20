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

## CI run on the hosted Intel runner

Label: `macos-26-intel` (Intel Core i7-8700B, macOS 26.6.1). Run 44815598268 on branch `ci/intel-slice`, workflow_dispatch.

```
Command: the `Intel Mac (x86_64 slice)` job (build, tests/intel-slice-test.sh with REQUIRE_INTEL=1, smoke suite)
Exit: 0
Output: job success, 10 min 41 s end to end (build 5 min 45 s, slice test 4 s, smoke suite 4 min 25 s)
        Mach-O count is 3 on the CI build because it uses --with-safari; the local run above built Quick Look only
        host: x86_64, Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz, macOS 26.6.1
        ok   the host is a native Intel Mac
        ok   3 Mach-O files, each with arm64 and x86_64
        ok   lipo -thin x86_64 gives an x86_64 Mach-O
        ok   heading page rendered under arch -x86_64
        ok   math typeset with inlined fonts under arch -x86_64
        intel-slice-test: 5 passed, 0 failed
        smoke: all 192 passed
Verdict: PASS
```

Two earlier runs of the same job failed on one smoke check, `--shot --offline: PNGs identical or missing`, and a probe run found the cause: the first launch of Python on a fresh Intel runner takes about 36 seconds, the smoke suite waits 5 seconds for its local image server, so the remote-image page rendered with no server and both PNGs matched. A `Warm up Python` step before the smoke suite pays that cold start; the suite itself is unchanged. That one run was green and under 15 minutes, but the same job on the PR run (44817489054) hung in the build step until the runner cancelled it at 24 minutes, with no log kept. One hang in four runs is not a reliable required check, so the job is NOT in `CI summary`'s `needs`: it reports on every PR, is not required, and has `timeout-minutes: 15`.

## CI negative control

```
Command: the same job on the same code before the Warm up Python step
Exit: 1
Output: FAIL: --shot --offline: online rc=0 offline rc=0, PNGs identical or missing
        smoke: 191 passed, 1 FAILED
Verdict: RED, as expected: the job fails when a check fails
```

## Reproduce

```
NO_INSTALL=1 integrations/build-safari.sh --with-safari
bash tests/intel-slice-test.sh <printed Spacedown.app path>
bash scripts/check.sh
```
