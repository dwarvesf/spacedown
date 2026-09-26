#!/usr/bin/env bash
# build-safari.sh: build + install the full native macOS bundle in ONE pass:
#
#   ~/Applications/Markdown Preview.app
#     ├─ MdPreviewDrop Extension.appex   Safari Web Extension (drag-drop)  [sandboxed]
#     └─ MarkdownPreviewQL.appex         Quick Look spacebar preview        [sandboxed]
#   ~/.local/libexec/mdpreview-render                           unsandboxed XPC render helper
#   ~/Library/LaunchAgents/foundation.d.mdpreview.render.plist  launch-on-demand
#
# Everything is signed adhoc (`-`) + hardened runtime + per-target entitlements;
# no Apple Developer team dependency.
#
# Why one script: the Safari ext and the QL appex live in the SAME app bundle.
# Two separate installers `rsync --delete`-stomped each other and re-signed the
# Safari ext without its sandbox, which is what kept it from loading. This is now
# the single source of truth for the native bundle.
#
# Architecture (why the helper exists): a Safari Web Extension MUST be sandboxed
# to load, and a sandboxed handler cannot Process-spawn pandoc. So the spawn
# moved to mdpreview-render, reached over XPC via a per-user LaunchAgent Mach
# service that launchd starts on demand.
#
# Usage: ./build-safari.sh [--with-safari]
#   (default)      the app with the Quick Look extension alone. Quick Look needs no
#                  Safari extension, render helper, LaunchAgent or md-open link.
#   --with-safari  also build the Safari drop extension and install its render
#                  helper + LaunchAgent (needs the md-preview CLI and pandoc).
#
# Env (used by scripts/release.sh):
#   SIGN_ID=<identity>  sign with this identity instead of adhoc, with a secure
#                       timestamp and the release app entitlements (no get-task-allow,
#                       which notarization rejects).
#   NO_INSTALL=1        stop after signing and print the built app's path.
set -euo pipefail
SIGN_ID="${SIGN_ID:--}"
NO_INSTALL="${NO_INSTALL:-0}"

SAFARI=0
case "${1:-}" in
  "") ;;
  --with-safari) SAFARI=1 ;;
  *) echo "usage: build-safari.sh [--with-safari]" >&2; exit 64 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="${HERE}/safari/MdPreviewDrop"
QLDIR="${HERE}/safari/quick-look"
ENT="${HERE}/safari/entitlements"
HELPER_SRC="${HERE}/safari/helper/mdpreview-render.swift"
PLIST_SRC="${HERE}/safari/helper/foundation.d.mdpreview.render.plist"
APP_NAME="Markdown Preview.app"
APP_DEST="${HOME}/Applications"
HELPER_DEST="${HOME}/.local/libexec/mdpreview-render"
AGENT_LABEL="foundation.d.mdpreview.render"
PLIST_DEST="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
QL_ID="foundation.d.mdpreview.quicklook"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
UID_NUM="$(id -u)"

command -v xcodebuild >/dev/null 2>&1 || { echo "build-safari: xcodebuild not found (install Xcode)" >&2; exit 1; }
command -v swiftc     >/dev/null 2>&1 || { echo "build-safari: swiftc not found (install Xcode)" >&2; exit 1; }
command -v xcodegen   >/dev/null 2>&1 || { echo "build-safari: xcodegen not found (brew install xcodegen)" >&2; exit 1; }
[[ -d "$PROJ/MdPreviewDrop.xcodeproj" ]] || { echo "build-safari: project missing at $PROJ" >&2; exit 1; }

mkdir -p "$PROJ/build"
if [[ $SAFARI -eq 1 ]]; then
  # md-open must be on PATH for the helper to find it at runtime.
  mkdir -p "${HOME}/.local/bin"
  ln -sfn "${HERE}/md-open" "${HOME}/.local/bin/md-open"
  echo "build-safari: symlinked md-open -> ~/.local/bin/md-open"

  # 1. Unsandboxed XPC render helper (adhoc signed, no entitlements, no runtime so
  #    its pandoc/python child processes stay unconstrained).
  echo "build-safari: compiling render helper..."
  swiftc -O "$HELPER_SRC" -o "$PROJ/build/mdpreview-render"
  codesign --force --sign - --timestamp=none "$PROJ/build/mdpreview-render"
fi

# 2. Container app + Safari extension, UNSIGNED (signed manually in step 5).
echo "build-safari: building app + Safari extension..."
xcodebuild -project "$PROJ/MdPreviewDrop.xcodeproj" \
  -scheme MdPreviewDrop -configuration Release \
  -derivedDataPath "$PROJ/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  INFOPLIST_KEY_NSHumanReadableCopyright="© 2026 Dwarves Foundation" \
  build >/dev/null
APP="$PROJ/build/Build/Products/Release/${APP_NAME}"
[[ -d "$APP" ]] || { echo "build-safari: app build produced nothing" >&2; exit 1; }

# 3. Quick Look appex (sibling xcodegen project), UNSIGNED. Share the VS Code CSS
#    and gate on the render-core node test first (same marked+katex glue it runs).
echo "build-safari: building Quick Look appex..."
cp -f "${HERE}/../assets/vscode-preview-head.html" "${QLDIR}/Resources/md-style.html"
if command -v node >/dev/null 2>&1; then
  ( cd "$QLDIR" && node test-render.js >/dev/null ) || { echo "build-safari: ql-render test FAILED" >&2; exit 1; }
fi
( cd "$QLDIR" && xcodegen generate >/dev/null )
xcodebuild -project "${QLDIR}/MarkdownPreviewQL.xcodeproj" \
  -scheme MarkdownPreviewQL -configuration Release \
  -derivedDataPath "${QLDIR}/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  build >/dev/null
QL_APPEX="${QLDIR}/build/Build/Products/Release/MarkdownPreviewQL.appex"
[[ -d "$QL_APPEX" ]] || { echo "build-safari: QL appex build produced nothing" >&2; exit 1; }

# 4. Embed the QL appex into the app.
mkdir -p "${APP}/Contents/PlugIns"
rsync -a --delete "$QL_APPEX" "${APP}/Contents/PlugIns/"
SAFARI_APPEX="${APP}/Contents/PlugIns/MdPreviewDrop Extension.appex"
if [[ $SAFARI -eq 0 && -d "$SAFARI_APPEX" ]]; then
  # The Xcode project always builds the Safari target; set it aside in the build dir.
  mkdir -p "$PROJ/build/set-aside"
  rsync -a --delete "$SAFARI_APPEX" "$PROJ/build/set-aside/"
  rm -rf "$SAFARI_APPEX"
fi

# 5. Sign adhoc + hardened runtime, OUTSIDE-IN (nested appex first, then the app
#    re-seals PlugIns). Safari appex carries the sandbox + mach-lookup exception.
APP_ENT="${ENT}/app.entitlements"
TIMESTAMP=()
if [[ "$SIGN_ID" != "-" ]]; then
  APP_ENT="${ENT}/app.release.entitlements"
  TIMESTAMP=(--timestamp)
fi
echo "build-safari: signing (${SIGN_ID} + runtime + entitlements)..."
# The ${a[@]+...} form keeps an empty array safe under set -u on macOS's bash 3.2.
sign() { codesign --force --sign "$SIGN_ID" --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --entitlements "$1" "$2"; }
sign "${QLDIR}/MarkdownPreviewQL.entitlements" "${APP}/Contents/PlugIns/MarkdownPreviewQL.appex"
[[ $SAFARI -eq 1 ]] && sign "${ENT}/extension.entitlements" "$SAFARI_APPEX"
sign "$APP_ENT"                                 "${APP}"
codesign --verify --deep --strict "$APP" || { echo "build-safari: signature verify failed" >&2; exit 1; }
if [[ "$NO_INSTALL" == "1" ]]; then
  echo "$APP"
  exit 0
fi

# 6. Install the app.
mkdir -p "$APP_DEST"
rsync -a --delete "$APP" "$APP_DEST/"
echo "build-safari: installed -> ${APP_DEST}/${APP_NAME}"

# 7. Install the helper binary + LaunchAgent (launch-on-demand Mach service).
if [[ $SAFARI -eq 1 ]]; then
  mkdir -p "$(dirname "$HELPER_DEST")"
  cp -f "$PROJ/build/mdpreview-render" "$HELPER_DEST"
  chmod +x "$HELPER_DEST"
  sed "s|__HELPER_BIN__|$HELPER_DEST|g" "$PLIST_SRC" > "$PLIST_DEST"
  launchctl bootout "gui/$UID_NUM/${AGENT_LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST"
  echo "build-safari: installed helper + bootstrapped LaunchAgent (on-demand)"
fi

# 8. Duplicate-row gotcha: xcodebuild already registered the
#    DerivedData app copy, so without this Safari shows the extension twice.
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -f "${APP_DEST}/${APP_NAME}"

# 9. Register + enable Quick Look. The explicit add matters: an OS upgrade has been
#    seen to drop the registration while leaving the app in place.
pluginkit -a "${APP_DEST}/${APP_NAME}/Contents/PlugIns/MarkdownPreviewQL.appex" 2>/dev/null || true
pluginkit -e use -i "$QL_ID" >/dev/null 2>&1 || true
if [[ $SAFARI -eq 0 ]]; then
  echo "build-safari: Quick Look ready. Select a .md in Finder and press space."
  exit 0
fi
# Launch the app once so Safari discovers the extension.
open "${APP_DEST}/${APP_NAME}"
echo "build-safari: launched once to register the Safari extension."

cat <<'EOF'

Finish in Safari (one-time):
  1. Safari > Settings... > Developer > tick "Allow unsigned extensions"
     (adhoc-signed = unsigned to Safari; resets each Safari restart until notarized)
  2. QUIT and relaunch Safari (it only rescans dev extensions at launch).
  3. Safari > Settings... > Extensions > tick "Markdown Preview".
  4. Click its toolbar button -> a dropzone tab opens -> drag a .md in.

Quick Look (spacebar preview) is enabled automatically; a fresh macOS may still need:
  System Settings > General > Login Items & Extensions > Quick Look > tick "Markdown Preview".
EOF
