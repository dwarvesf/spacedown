#!/usr/bin/env bash
# intel-slice-test.sh: the universal build really carries an x86_64 slice and that slice
# runs. CI runs it on a GitHub-hosted Intel macOS runner after a NO_INSTALL build.
#
#   bash tests/intel-slice-test.sh <built Spacedown.app>
#
# Checks, in order:
#   1. every Mach-O file in the app has both an arm64 and an x86_64 slice (lipo -archs)
#   2. the x86_64 slice of the Quick Look extension executable thins out as x86_64
#   3. the bundled CLI renders a fixture under `arch -x86_64`: the page has the heading,
#      the KaTeX markup and the inlined math fonts, so osascript (JavaScriptCore) and the
#      app's own render core run on the Intel slice
#   4. with REQUIRE_INTEL=1 (CI): the machine itself is an Intel Mac, so check 3 is not
#      Rosetta on Apple silicon
# bash 3.2 safe. Exit 0: all passed. Exit 1: a check failed. Exit 64: bad usage.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"
[[ -d "$APP/Contents" ]] || { echo "usage: intel-slice-test.sh <Spacedown.app>" >&2; exit 64; }
APP="$(cd "$APP" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/intel-slice.XXXXXX")"
pass=0; fail=0
ok() { echo "  ok   $1"; pass=$((pass + 1)); }
no() { echo "  FAIL $1"; fail=$((fail + 1)); }

echo "host: $(uname -m), $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown cpu), macOS $(sw_vers -productVersion)"
if [[ "${REQUIRE_INTEL:-0}" == "1" ]]; then
    translated="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"
    if [[ "$(uname -m)" == "x86_64" && "$translated" != "1" ]]; then
        ok "the host is a native Intel Mac"
    else
        no "REQUIRE_INTEL=1 but this host is $(uname -m) (translated=$translated)"
    fi
fi

echo "[slices] every Mach-O in the app is universal"
machos=0; thin=""
while IFS= read -r f; do
    kind="$(file -b "$f")"
    case "$kind" in
    *Mach-O*) ;;
    *) continue ;;
    esac
    machos=$((machos + 1))
    archs="$(lipo -archs "$f" 2>/dev/null || echo none)"
    case " $archs " in *" arm64 "*) has_arm=1 ;; *) has_arm=0 ;; esac
    case " $archs " in *" x86_64 "*) has_x86=1 ;; *) has_x86=0 ;; esac
    if [[ $has_arm -eq 0 || $has_x86 -eq 0 ]]; then
        thin="${thin}    ${f#"$APP"/}: ${archs}
"
    fi
done < <(find "$APP" -type f)
if [[ "$machos" -gt 0 && -z "$thin" ]]; then
    ok "$machos Mach-O files, each with arm64 and x86_64"
else
    no "$machos Mach-O files; not universal:"
    printf '%s' "$thin"
fi

echo "[thin] the Quick Look extension executable has a real x86_64 slice"
QL_EXE="$(find "$APP/Contents/PlugIns/SpacedownQL.appex/Contents/MacOS" -type f 2>/dev/null | head -1)"
if [[ -n "$QL_EXE" ]] && lipo -thin x86_64 "$QL_EXE" -output "$T/ql-x86_64" 2>/dev/null \
    && file -b "$T/ql-x86_64" | grep -q 'x86_64'; then
    ok "lipo -thin x86_64 gives an x86_64 Mach-O"
else
    no "no x86_64 slice in the Quick Look extension executable (${QL_EXE:-not found})"
fi

echo "[render] the bundled CLI renders on the x86_64 slice"
CLI="$APP/Contents/Resources/cli/bin/spacedown"
if [[ ! -x "$CLI" ]]; then
    no "the app has no bundled CLI at Contents/Resources/cli/bin/spacedown"
else
    cp "$ROOT/tests/fixture/math-offline.md" "$T/m.md"
    printf '# Intel slice heading\n\nbody text\n' > "$T/h.md"
    out="$(arch -x86_64 "$CLI" "$T/h.md" --out "$T/h.html" --no-open 2>&1)"; rc=$?
    if [[ $rc -eq 0 && -s "$T/h.html" ]] && grep -q 'Intel slice heading' "$T/h.html"; then
        ok "heading page rendered under arch -x86_64"
    else
        no "render exited $rc: $out"
    fi
    out="$(arch -x86_64 "$CLI" "$T/m.md" --out "$T/m.html" --no-open 2>&1)"; rc=$?
    if [[ $rc -eq 0 ]] && grep -q '<span class="katex">' "$T/m.html" && grep -q 'data:font/woff2;base64,' "$T/m.html"; then
        ok "math typeset with inlined fonts under arch -x86_64"
    else
        no "math render exited $rc: $out"
    fi
fi

echo "intel-slice-test: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
