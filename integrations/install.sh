#!/usr/bin/env bash
# install.sh: wire up the two md-preview "just open it" integrations on macOS.
#
#   1. Finder app  -> compiles Spacedown Opener.app (an Apple-Event open-handler) and,
#                     with --set-default, registers it as the default .md handler.
#   2. Extension   -> installs the native-messaging host manifest into every
#                     installed Chromium browser's NativeMessagingHosts dir, with
#                     the path + extension-ID filled in. (You still load the
#                     unpacked extension once, in the browser, by hand.)
#
# Idempotent: re-running re-compiles the app and re-writes the manifests.
#
# Usage:
#   ./install.sh                  # install app + native host; offer once (TTY) to set default
#   ./install.sh --set-default    # explicitly make Spacedown Opener the default .md app
#   ./install.sh --revert-default # restore the .md handler we replaced (one command)
#   ./install.sh --uninstall      # remove app, manifests, and (if set) the default
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MD_OPEN="${HERE}/md-open"
APP_SRC="${HERE}/finder-app/SpacedownOpener.applescript"
# The bundle is named "Spacedown Opener.app": macOS's default-handler / Open-With dialogs
# use the bundle FILENAME (not CFBundleDisplayName), so the name must live in the filename.
APP_OUT="${HERE}/finder-app/Spacedown Opener.app"
HOST_BIN="${HERE}/extension/native-host/md-preview-host"
HOST_TPL="${HERE}/extension/native-host/foundation.d.spacedown.json.template"
HOST_NAME="foundation.d.spacedown"
EXTENSION_ID="mhifeggicglofancjnjmkgihedkddnpn"  # derived from extension/manifest.json "key"
MD_UTI="net.daringfireball.markdown"
# The .md extension can resolve through either UTI depending on the machine, and our app
# claims both, so set/revert must cover both or the `md` binding won't flip cleanly.
MD_UTIS=( "net.daringfireball.markdown" "public.markdown" )
HANDLER_BUNDLE="foundation.d.spacedown.opener"            # the Finder Open-With app, set on Spacedown Opener.app below
STATE_DIR="${HOME}/.config/md-preview"
FIRSTRUN_MARKER="${STATE_DIR}/handler-offered"    # so the first-run offer asks exactly once
PREV_HANDLER_FILE="${STATE_DIR}/prev-md-handler"  # snapshot of the handler we replaced, for revert

# Chromium browsers whose native-messaging dir we populate if the browser exists.
# Format: "AppName|Library/Application Support/<subdir>"
BROWSERS=(
  "Microsoft Edge|Microsoft Edge"
  "Google Chrome|Google/Chrome"
  "Brave Browser|BraveSoftware/Brave-Browser"
  "Arc|Arc/User Data"
)

log() { echo "install: $*"; }
die() { echo "install: $*" >&2; exit 1; }

# Current default app (bundle id) for .md, empty if none. duti -x prints
# app-name / path / bundle-id; the bundle id is the last line.
current_md_handler() { duti -x md 2>/dev/null | tail -1; }

# Register our app as the default .md handler, snapshotting the prior handler so
# revert restores exactly what was there (not a guessed editor). Prints the revert.
set_default_handler() {
  command -v duti >/dev/null 2>&1 || die "--set-default needs duti (brew install duti)"
  mkdir -p "$STATE_DIR"
  local prev; prev="$(current_md_handler)"
  if [[ -n "$prev" && "$prev" != "$HANDLER_BUNDLE" ]]; then
    printf '%s\n' "$prev" > "$PREV_HANDLER_FILE"
  fi
  local uti; for uti in "${MD_UTIS[@]}"; do duti -s "$HANDLER_BUNDLE" "$uti" all; done
  log "Spacedown Opener is now the DEFAULT app for .md files (handler: ${HANDLER_BUNDLE})."
  if [[ -n "$prev" && "$prev" != "$HANDLER_BUNDLE" ]]; then
    log "Revert in one command:  ./install.sh --revert-default   (restores ${prev})"
    log "  or manually:  duti -s ${prev} ${MD_UTI} all"
  else
    log "Revert:  duti -s <your-editor-bundle-id> ${MD_UTI} all"
  fi
}

# Restore the handler we replaced (from the snapshot, or an explicit bundle id arg).
revert_default_handler() {
  command -v duti >/dev/null 2>&1 || die "--revert-default needs duti"
  local prev="${1:-}"
  [[ -z "$prev" && -f "$PREV_HANDLER_FILE" ]] && prev="$(cat "$PREV_HANDLER_FILE")"
  [[ -n "$prev" ]] || die "no saved prior .md handler; pass one: --revert-default <bundle-id>"
  local uti; for uti in "${MD_UTIS[@]}"; do duti -s "$prev" "$uti" all; done
  rm -f "$PREV_HANDLER_FILE"
  log "Reverted default .md handler to ${prev}."
  exit 0
}

uninstall() {
  log "removing Spacedown Opener.app"
  rm -rf "$APP_OUT" "$LEGACY_APP"
  for entry in "${BROWSERS[@]}"; do
    sub="${entry#*|}"
    f="${HOME}/Library/Application Support/${sub}/NativeMessagingHosts/${HOST_NAME}.json"
    [[ -f "$f" ]] && { rm -f "$f"; log "removed native host manifest: $f"; }
  done
  if command -v duti >/dev/null 2>&1; then
    if [[ -f "$PREV_HANDLER_FILE" ]]; then
      log "Restore the .md handler we replaced:  ./install.sh --revert-default   (-> $(cat "$PREV_HANDLER_FILE"))"
    else
      log "NOTE: default .md handler not auto-reverted. Set your editor back with e.g.:"
      log "  duti -s com.visualstudio.code.oss ${MD_UTI} all   # VSCodium"
    fi
  fi
  log "uninstall done."
  exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall
[[ "${1:-}" == "--revert-default" ]] && revert_default_handler "${2:-}"

command -v osacompile >/dev/null 2>&1 || die "osacompile not found (ships with macOS)"
[[ -f "$MD_OPEN" ]] || die "md-open wrapper missing at $MD_OPEN"
chmod +x "$MD_OPEN" "$HOST_BIN"

# --- 1. compile the Finder app with the md-open path injected ---
log "compiling Spacedown Opener.app"
tmp_scpt="$(mktemp -t SpacedownOpener).applescript"
sed "s#__MD_OPEN__#${MD_OPEN}#g" "$APP_SRC" > "$tmp_scpt"
rm -rf "$APP_OUT"
osacompile -o "$APP_OUT" "$tmp_scpt"
rm -f "$tmp_scpt"
# Declare the app as a viewer/editor for markdown + plain text so it shows up in
# Finder's "Open With" and is eligible as a default handler.
plist="${APP_OUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string foundation.d.spacedown.opener" "$plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier foundation.d.spacedown.opener" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Spacedown Opener" "$plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Spacedown Opener" "$plist"
# CFBundleName too, so every surface (Get Info, Open With, the change-all dialog) reads
# "Spacedown Opener", never the "SpacedownOpener" source filename stem.
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Spacedown Opener" "$plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Spacedown Opener" "$plist"
# Declare the app as a markdown document handler. Without CFBundleDocumentTypes /
# LSItemContentTypes, LaunchServices ignores `duti -s` (an app can only be the default
# for a type it claims to open). The fresh osacompile bundle has none, so plain Add works.
/usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Markdown Document'" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string ${MD_UTI}" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.markdown" "$plist"
log "built $APP_OUT (display name: Spacedown Opener; declares ${MD_UTI})"
# Register it with LaunchServices so Finder sees it immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_OUT" 2>/dev/null || true

# --- 2. install native-messaging host manifests ---
[[ -f "$HOST_TPL" ]] || die "host manifest template missing at $HOST_TPL"
installed_any=0
for entry in "${BROWSERS[@]}"; do
  appname="${entry%%|*}"; sub="${entry#*|}"
  [[ -d "/Applications/${appname}.app" ]] || continue
  dir="${HOME}/Library/Application Support/${sub}/NativeMessagingHosts"
  mkdir -p "$dir"
  sed -e "s#__HOST_PATH__#${HOST_BIN}#g" -e "s#__EXTENSION_ID__#${EXTENSION_ID}#g" \
    "$HOST_TPL" > "${dir}/${HOST_NAME}.json"
  log "installed native host for ${appname}: ${dir}/${HOST_NAME}.json"
  installed_any=1
done
[[ "$installed_any" == "1" ]] || log "no Chromium browser found; skipped native host install"

# --- 3. default .md handler: explicit flag, or a consent-gated first-run offer ---
# Never hijack double-click silently. --set-default is explicit consent; a bare
# interactive run offers ONCE (guarded by a first-run marker); non-interactive does nothing.
if [[ "${1:-}" == "--set-default" ]]; then
  set_default_handler
elif [[ -t 0 && -t 1 && ! -f "$FIRSTRUN_MARKER" ]]; then
  mkdir -p "$STATE_DIR"; : > "$FIRSTRUN_MARKER"
  printf 'install: make "Spacedown Opener" the default app for .md files? [y/N] ' >&2
  read -r reply
  if [[ "$reply" =~ ^[Yy] ]]; then
    set_default_handler
  else
    log "Left your current .md handler untouched. Set it later:  ./install.sh --set-default"
  fi
else
  log "Spacedown Opener installed but NOT set as default (double-click still opens your editor)."
  log "To make it the default .md app:  ./install.sh --set-default   (revert: --revert-default)"
  log "Either way it now appears under Finder right-click > Open With > Spacedown Opener."
fi

cat <<EOF

install: done. Next step for the browser drag-drop (one-time, manual):
  1. Open  edge://extensions  (or chrome://extensions)
  2. Toggle "Developer mode" on
  3. "Load unpacked" -> select:
       ${HERE}/extension
  4. Confirm the extension ID is:  ${EXTENSION_ID}
     (if it differs, re-run this script after editing EXTENSION_ID, or load in
      the browser you installed the native host for)
  5. Click the extension's toolbar icon -> a dropzone tab opens -> drag a .md in.
EOF
