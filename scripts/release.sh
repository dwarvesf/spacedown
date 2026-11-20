#!/usr/bin/env bash
# release.sh: build the Quick Look app, sign it with Developer ID, notarize, staple,
# zip + dmg, and publish both as a GitHub release. Same shape as Hacker Bar's
# scripts/release-direct.sh, without Sparkle (Homebrew handles updates).
#
# Preconditions (checked, not created):
#   - the Developer ID Application identity for TEAM_ID in the login keychain
#   - a notarytool keychain profile: xcrun notarytool store-credentials <name>
#   - a clean working tree
#
# Env (defaults shown):
#   TEAM_ID=W777S7V8TN
#   SIGN_ID                 default: the one "Developer ID Application: <name> (TEAM_ID)"
#                           identity in the keychain, found by TEAM_ID
#   NOTARY_PROFILE          a notarytool keychain profile name (no default), or
#   NOTARY_KEY=<.p8 path> NOTARY_KEY_ID NOTARY_ISSUER   an API key (headless)
#   REPO=consolelabs/spacedown
#   DRAFT=0                 1 = create the release as a draft
#   PUBLISH=1               0 = stop after the notarized zip, no GitHub release
#   APP_BUDGET_BYTES / DMG_BUDGET_BYTES   override the size budget in scripts/size-budget, which
#                           fails the release when the app or the dmg grows past it
#   PRUNE_OLD_RELEASES=0    1 = after publishing, delete every older GitHub release and its
#                           tag. By default older releases and tags are kept.
#
# The release notes are CHANGELOG.md's section for the version (scripts/release-notes.sh),
# plus the zip's sha256; a version with no section stops the release before the build.
#
# Mac App Store mode (--mas): builds the Quick Look-only app, signs it with Apple
# Distribution plus the Mac App Store provisioning profiles, packages a signed .pkg,
# and (UPLOAD=1) uploads it to App Store Connect. Extra preconditions and env:
#   MAS_SIGN_ID             default: the "Apple Distribution: <name> (TEAM_ID)" identity in the keychain
#   INSTALLER_ID            default: the "3rd Party Mac Developer Installer: <name> (TEAM_ID)" identity
#   PROFILE_DIR=~/.local/share/spacedown-signing   holds <bundle id>.provisionprofile
#                                                   for the app and the Quick Look extension
#   BUILD_NUMBER=<yyyymmddHHMM>   CFBundleVersion; must grow with every upload
#   UPLOAD=0                1 = upload with altool; needs ASC_KEY_ID, ASC_ISSUER_ID and
#                           the key file under API_PRIVATE_KEYS_DIR (altool's lookup)
# The store build drops the Quick Look extension's read-only home exception, so images
# next to a previewed file do not render there; the direct download keeps them.
#
# Usage: scripts/release.sh [--mas] [--dry-run] [x.y.z]   (default: MARKETING_VERSION in quick-look/project.yml)
#   --dry-run  print the release notes and whether older releases would be kept, run every
#              precondition check (versions, identities, profiles, notary credentials), print
#              what would be used, then stop: no build, no signing, no upload, no release.
set -euo pipefail

MAS=0
DRY_RUN=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --mas) MAS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "usage: scripts/release.sh [--mas] [--dry-run] [x.y.z]" >&2; exit 64 ;;
  esac
  shift
done

TEAM_ID="${TEAM_ID:-W777S7V8TN}"
SIGN_ID="${SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
# Notary auth: an App Store Connect API key when NOTARY_KEY (a .p8 path), NOTARY_KEY_ID and
# NOTARY_ISSUER are set, else the keychain profile. The key works headless; a keychain
# profile cannot be stored without a GUI session on some hosts.
if [[ -n "${NOTARY_KEY:-}" ]]; then
  NOTARY_AUTH=( --key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID unset}" --issuer "${NOTARY_ISSUER:?NOTARY_ISSUER unset}" )
elif [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_AUTH=( --keychain-profile "$NOTARY_PROFILE" )
else
  NOTARY_AUTH=()
fi
REPO="${REPO:-consolelabs/spacedown}"
DRAFT="${DRAFT:-0}"
PUBLISH="${PUBLISH:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$ROOT/integrations/safari/quick-look/project.yml")}"
TAG="v$VERSION"
DIST="$ROOT/build/release/$VERSION"
APP_NAME="Spacedown.app"
ZIP="$DIST/Spacedown-$VERSION-macos.zip"
DMG="$DIST/Spacedown-$VERSION.dmg"

die() { echo "release: $*" >&2; exit 1; }
# Capture, then match: `cmd | grep -q` under pipefail fails when grep exits early and
# the writer takes SIGPIPE, which reads as a failed check on a passing result.
has() { printf '%s' "$1" | grep -qF -- "$2"; }
# find_identity <kind> [find-identity flags]: the first keychain identity named
# "<kind>: <name> (TEAM_ID)", so no legal name is hardcoded here. Empty when there is none.
find_identity() {
  local kind="$1"; shift
  security find-identity -v "$@" | awk -v want="$kind: " -v team="($TEAM_ID)\"" '
    found { next }
    { q = index($0, "\""); if (!q) next; name = substr($0, q + 1)
      if (index(name, want) == 1 && substr(name, length(name) - length(team) + 1) == team) {
        print substr(name, 1, length(name) - 1); found = 1 } }'
}

# The browser extensions and the CLI carry their own version strings; a release
# that skips them ships stale labels, so refuse until every one matches.
stale=()
for manifest in "$ROOT/integrations/extension/manifest.json" \
                "$ROOT/integrations/safari/SpacedownDrop/SpacedownDrop Extension/Resources/manifest.json"; do
  v="$(awk -F'"' '/"version"/ {print $4; exit}' "$manifest")"
  [[ "$v" == "$VERSION" ]] || stale+=( "${manifest#"$ROOT/"} ($v)" )
done
v="$(awk -F'"' '/^VERSION=/ {print $2; exit}' "$ROOT/bin/spacedown")"
[[ "$v" == "$VERSION" ]] || stale+=( "bin/spacedown ($v)" )
[[ ${#stale[@]} -eq 0 ]] || die "version $VERSION not set in: ${stale[*]}"

# --- Mac App Store ---------------------------------------------------------------
if [[ $MAS -eq 1 ]]; then
  MAS_SIGN_ID="${MAS_SIGN_ID:-$(find_identity "Apple Distribution" || true)}"
  INSTALLER_ID="${INSTALLER_ID:-$(find_identity "3rd Party Mac Developer Installer" || true)}"
  PROFILE_DIR="${PROFILE_DIR:-$HOME/.local/share/spacedown-signing}"
  BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
  UPLOAD="${UPLOAD:-0}"
  APP_ID="dfoundation.spacedown"
  QL_ID="dfoundation.spacedown.quicklook"
  MDIST="$ROOT/build/release-mas/$VERSION"
  PKG="$MDIST/Spacedown-$VERSION.pkg"
  ENT="$ROOT/integrations/safari/entitlements"
  QL_ENT_SRC="$ROOT/integrations/safari/quick-look/SpacedownQL.entitlements"

  [[ -n "$VERSION" ]] || die "no version given and none found in project.yml"
  [[ -n "$MAS_SIGN_ID" ]] || die "no Apple Distribution identity for team $TEAM_ID in the keychain (or set MAS_SIGN_ID)"
  [[ -n "$INSTALLER_ID" ]] || die "no 3rd Party Mac Developer Installer identity for team $TEAM_ID in the keychain (or set INSTALLER_ID)"
  idents="$(security find-identity -v)"
  has "$idents" "\"$MAS_SIGN_ID\"" || die "signing identity missing: $MAS_SIGN_ID"
  has "$idents" "\"$INSTALLER_ID\"" || die "installer identity missing: $INSTALLER_ID"
  for id in "$APP_ID" "$QL_ID"; do
    [[ -f "$PROFILE_DIR/$id.provisionprofile" ]] || die "profile missing: $PROFILE_DIR/$id.provisionprofile"
  done
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "dirty tree; commit first"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "dry run: $VERSION ($BUILD_NUMBER), sign: $MAS_SIGN_ID, installer: $INSTALLER_ID, profiles in $PROFILE_DIR"
    echo "dry run: stopping before the build; nothing signed or uploaded"
    exit 0
  fi

  echo "== build (Quick Look only)"
  # BUNDLE_CLI=0: the store app is sandboxed and Homebrew never links it, so no CLI inside.
  BUILT="$(SKIN_CSS= BUNDLE_CLI=0 NO_INSTALL=1 bash "$ROOT/integrations/build-safari.sh" | tail -1)"
  [[ -d "$BUILT" ]] || die "build did not report an app path"
  [[ ! -e "$BUILT/Contents/PlugIns/SpacedownDrop Extension.appex" ]] || die "the Safari drop extension is in the store build (it is opt-in: build-safari.sh --with-safari)"
  mkdir -p "$MDIST"
  rsync -a --delete "$BUILT" "$MDIST/"
  APP="$MDIST/$APP_NAME"
  APPEX="$APP/Contents/PlugIns/SpacedownQL.appex"
  "$ROOT/scripts/size-budget" "$APP" || die "the store app is over its size budget (scripts/size-budget)"

  echo "== version $VERSION ($BUILD_NUMBER), profiles, entitlements"
  for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
      -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"
  done
  cp -f "$PROFILE_DIR/$APP_ID.provisionprofile" "$APP/Contents/embedded.provisionprofile"
  cp -f "$PROFILE_DIR/$QL_ID.provisionprofile" "$APPEX/Contents/embedded.provisionprofile"
  APP_ENT_MAS="$MDIST/app.entitlements"
  QL_ENT_MAS="$MDIST/ql.entitlements"
  cp -f "$ENT/app.release.entitlements" "$APP_ENT_MAS"
  cp -f "$QL_ENT_SRC" "$QL_ENT_MAS"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.temporary-exception.files.home-relative-path.read-only" "$QL_ENT_MAS" 2>/dev/null || true
  for pair in "$APP_ENT_MAS:$APP_ID" "$QL_ENT_MAS:$QL_ID"; do
    f="${pair%%:*}"; bid="${pair#*:}"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$bid" \
      -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$f"
  done

  echo "== sign ($MAS_SIGN_ID)"
  codesign --force --sign "$MAS_SIGN_ID" --options runtime --entitlements "$QL_ENT_MAS" "$APPEX"
  codesign --force --sign "$MAS_SIGN_ID" --options runtime --entitlements "$APP_ENT_MAS" "$APP"
  codesign --verify --deep --strict "$APP" || die "signature verify failed"

  echo "== package"
  # macOS 26+ tags every file this build writes with com.apple.provenance, which
  # cannot be removed, and pkgbuild serialises it as ._ AppleDouble entries that the
  # App Store rejects. Keep productbuild's Distribution and PackageInfo, rebuild the
  # component Payload with cpio (COPYFILE_DISABLE) and a Bom without the ._ rows,
  # then flatten and sign again.
  PW="$(mktemp -d)"
  productbuild --component "$APP" /Applications "$PW/raw.pkg" >/dev/null 2>&1
  pkgutil --expand "$PW/raw.pkg" "$PW/x"
  COMP="$PW/x/$APP_ID.pkg"
  mkdir "$PW/root"
  ditto "$APP" "$PW/root/$APP_NAME"
  ( cd "$PW/root" && find . | COPYFILE_DISABLE=1 cpio -o --format odc -R 0:0 2>/dev/null | gzip -9 -c > "$COMP/Payload" )
  lsbom "$COMP/Bom" | grep -v '/\._' | sed $'1s/^\\.\t0\t/.\t40755\t/' > "$PW/bom.txt"
  mkbom -i "$PW/bom.txt" "$COMP/Bom"
  pkgutil --flatten "$PW/x" "$PW/unsigned.pkg"
  productsign --sign "$INSTALLER_ID" "$PW/unsigned.pkg" "$PKG" >/dev/null
  ! has "$(pkgutil --payload-files "$PKG")" "/._" || die "package payload still has AppleDouble entries"
  has "$(pkgutil --check-signature "$PKG")" "Status: signed by a certificate trusted" \
    || has "$(pkgutil --check-signature "$PKG")" "3rd Party Mac Developer Installer" \
    || die "package signature check failed"
  echo "pkg: $PKG"

  [[ "$UPLOAD" == "1" ]] || { echo "release: UPLOAD=0, stopping before App Store Connect"; exit 0; }
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || die "UPLOAD=1 needs ASC_KEY_ID and ASC_ISSUER_ID"
  echo "== upload"
  xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "done: $VERSION ($BUILD_NUMBER) uploaded to App Store Connect"
  exit 0
fi

# --- notes: printed by a dry run before any check that needs a credential --------
[[ -n "$VERSION" ]] || die "no version given and none found in project.yml"
NOTES="$("$ROOT/scripts/release-notes.sh" "$VERSION")" \
  || die "no release notes for $VERSION: add a \"## [$VERSION]\" section to CHANGELOG.md"
PRUNE="${PRUNE_OLD_RELEASES:-0}"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run: release notes for $TAG (from CHANGELOG.md), then the zip's sha256:"
  printf '%s\n' "$NOTES" | sed 's/^/  | /'
  if [[ "$PRUNE" == "1" ]]; then
    echo "dry run: older releases and their tags would be DELETED (PRUNE_OLD_RELEASES=1)"
  else
    echo "dry run: older releases and their tags are kept (PRUNE_OLD_RELEASES=1 deletes them)"
  fi
fi

# --- preconditions ------------------------------------------------------------
[[ -n "$SIGN_ID" ]] || SIGN_ID="$(find_identity "Developer ID Application" -p codesigning || true)"
[[ -n "$SIGN_ID" ]] || die "no Developer ID Application identity for team $TEAM_ID in the keychain (or set SIGN_ID)"
has "$(security find-identity -v -p codesigning)" "\"$SIGN_ID\"" \
  || die "signing identity missing: $SIGN_ID"
[[ ${#NOTARY_AUTH[@]} -gt 0 ]] \
  || die "no notary credentials: set NOTARY_PROFILE to a notarytool keychain profile (xcrun notarytool store-credentials <name>), or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER"
xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 \
  || die "notary credentials rejected: check NOTARY_PROFILE, or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "dirty tree; commit first"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run: $TAG, sign: $SIGN_ID, notary: ${NOTARY_AUTH[0]} (credentials accepted), repo: $REPO"
  echo "dry run: stopping before the build; nothing signed, notarized or published"
  exit 0
fi

# --- build + sign ---------------------------------------------------------------
echo "== build + sign ($SIGN_ID)"
# SKIN_CSS is blanked so a personal skin set in the shell never ships in a release.
BUILT="$(SKIN_CSS= SIGN_ID="$SIGN_ID" NO_INSTALL=1 bash "$ROOT/integrations/build-safari.sh" | tail -1)"
[[ -d "$BUILT" ]] || die "build did not report an app path"
# The release app is Quick Look only; the Safari drop extension stays behind build-safari.sh --with-safari.
[[ ! -e "$BUILT/Contents/PlugIns/SpacedownDrop Extension.appex" ]] || die "the Safari drop extension is in the release build"
mkdir -p "$DIST"
rsync -a --delete "$BUILT" "$DIST/"
APP="$DIST/$APP_NAME"
has "$(codesign -dvv "$APP" 2>&1)" "Authority=Developer ID Application" \
  || die "app is not signed with a Developer ID Application identity"
# Fail on growth before the notary round trip, not after it.
"$ROOT/scripts/size-budget" "$APP" || die "the app is over its size budget (scripts/size-budget)"

# --- notarize + staple ----------------------------------------------------------
echo "== notarize"
ditto -c -k --keepParent "$APP" "$DIST/submit.zip"
RESULT="$(xcrun notarytool submit "$DIST/submit.zip" "${NOTARY_AUTH[@]}" \
  --wait --output-format json)"
STATUS="$(printf '%s' "$RESULT" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
  SUB_ID="$(printf '%s' "$RESULT" | /usr/bin/plutil -extract id raw -o - - 2>/dev/null || true)"
  [[ -n "$SUB_ID" ]] && xcrun notarytool log "$SUB_ID" "${NOTARY_AUTH[@]}" >&2 || true
  die "notarization status: ${STATUS:-unknown}"
fi
xcrun stapler staple "$APP"
has "$(spctl -a -vv -t exec "$APP" 2>&1 || true)" "source=Notarized Developer ID" \
  || die "Gatekeeper does not accept the stapled app"

echo "== zip"
rm -f "$DIST/submit.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "zip: $ZIP"
echo "sha256: $SHA"

# --- dmg: drag-to-Applications image, itself signed, notarized and stapled --------
echo "== dmg"
DSTAGE="$(mktemp -d)"
ditto "$APP" "$DSTAGE/$APP_NAME"
ln -s /Applications "$DSTAGE/Applications"
hdiutil create -volname Spacedown -srcfolder "$DSTAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
"$ROOT/scripts/size-budget" "$APP" "$DMG" || die "the app or the dmg is over its size budget (scripts/size-budget)"
DRESULT="$(xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait 2>&1 || true)"
has "$DRESULT" "status: Accepted" || { echo "$DRESULT" >&2; die "dmg notarization not accepted"; }
xcrun stapler staple "$DMG" >/dev/null
has "$(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true)" "source=Notarized Developer ID" \
  || die "Gatekeeper does not accept the dmg"
echo "dmg: $DMG"

# --- github release -------------------------------------------------------------
[[ "$PUBLISH" == "1" ]] || { echo "release: PUBLISH=0, stopping before the GitHub release"; exit 0; }
DRAFT_FLAG=()
[[ "$DRAFT" == "1" ]] && DRAFT_FLAG=(--draft)
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "release $TAG already exists on $REPO"
fi
gh release create "$TAG" "$ZIP" "$DMG" --repo "$REPO" --title "Spacedown $VERSION" \
  --notes "$NOTES

sha256: \`$SHA\`" ${DRAFT_FLAG[@]+"${DRAFT_FLAG[@]}"}

# --- prune: only on request, older releases and tags stay by default ---------------
if [[ "$PRUNE" == "1" && "$DRAFT" != "1" ]]; then
  OLD_TAGS="$(gh release list --repo "$REPO" --limit 100 --json tagName -q '.[].tagName')"
  for old in $OLD_TAGS; do
    [[ "$old" == "$TAG" ]] && continue
    gh release delete "$old" --repo "$REPO" --yes --cleanup-tag
    echo "removed older release $old"
  done
fi
echo "done: $TAG on $REPO"
