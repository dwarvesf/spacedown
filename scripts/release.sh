#!/usr/bin/env bash
# release.sh: build the Quick Look app, sign it with Developer ID, notarize, staple,
# zip, and publish it as a GitHub release. Same shape as Hacker Bar's
# scripts/release-direct.sh, without Sparkle (Homebrew handles updates).
#
# Preconditions (checked, not created):
#   - the Developer ID Application identity for TEAM_ID in the login keychain
#   - a notarytool keychain profile: xcrun notarytool store-credentials <name>
#   - a clean working tree
#
# Env (defaults shown):
#   TEAM_ID=W777S7V8TN
#   SIGN_ID="Developer ID Application: Dwarves Foundation Company Limited ($TEAM_ID)"
#   NOTARY_PROFILE=DWARVES_NOTARY
#   REPO=dwarvesf/spacedown
#   DRAFT=0                 1 = create the release as a draft
#   PUBLISH=1               0 = stop after the notarized zip, no GitHub release
#
# Mac App Store mode (--mas): builds the Quick Look-only app, signs it with Apple
# Distribution plus the Mac App Store provisioning profiles, packages a signed .pkg,
# and (UPLOAD=1) uploads it to App Store Connect. Extra preconditions and env:
#   MAS_SIGN_ID="Apple Distribution: Dwarves Foundation Company Limited ($TEAM_ID)"
#   INSTALLER_ID="3rd Party Mac Developer Installer: Dwarves Foundation Company Limited ($TEAM_ID)"
#   PROFILE_DIR=~/.local/share/spacedown-signing   holds <bundle id>.provisionprofile
#                                                   for the app and the Quick Look extension
#   BUILD_NUMBER=<yyyymmddHHMM>   CFBundleVersion; must grow with every upload
#   UPLOAD=0                1 = upload with altool; needs ASC_KEY_ID, ASC_ISSUER_ID and
#                           the key file under API_PRIVATE_KEYS_DIR (altool's lookup)
# The store build drops the Quick Look extension's read-only home exception, so images
# next to a previewed file do not render there; the direct download keeps them.
#
# Usage: scripts/release.sh [--mas] [x.y.z]   (default: MARKETING_VERSION in quick-look/project.yml)
set -euo pipefail

MAS=0
if [[ "${1:-}" == "--mas" ]]; then MAS=1; shift; fi

TEAM_ID="${TEAM_ID:-W777S7V8TN}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Dwarves Foundation Company Limited ($TEAM_ID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-DWARVES_NOTARY}"
REPO="${REPO:-dwarvesf/spacedown}"
DRAFT="${DRAFT:-0}"
PUBLISH="${PUBLISH:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$ROOT/integrations/safari/quick-look/project.yml")}"
TAG="v$VERSION"
DIST="$ROOT/build/release/$VERSION"
APP_NAME="Spacedown.app"
ZIP="$DIST/Spacedown-$VERSION-macos.zip"

die() { echo "release: $*" >&2; exit 1; }
# Capture, then match: `cmd | grep -q` under pipefail fails when grep exits early and
# the writer takes SIGPIPE, which reads as a failed check on a passing result.
has() { printf '%s' "$1" | grep -qF -- "$2"; }

# --- Mac App Store ---------------------------------------------------------------
if [[ $MAS -eq 1 ]]; then
  MAS_SIGN_ID="${MAS_SIGN_ID:-Apple Distribution: Dwarves Foundation Company Limited ($TEAM_ID)}"
  INSTALLER_ID="${INSTALLER_ID:-3rd Party Mac Developer Installer: Dwarves Foundation Company Limited ($TEAM_ID)}"
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
  idents="$(security find-identity -v)"
  has "$idents" "\"$MAS_SIGN_ID\"" || die "signing identity missing: $MAS_SIGN_ID"
  has "$idents" "\"$INSTALLER_ID\"" || die "installer identity missing: $INSTALLER_ID"
  for id in "$APP_ID" "$QL_ID"; do
    [[ -f "$PROFILE_DIR/$id.provisionprofile" ]] || die "profile missing: $PROFILE_DIR/$id.provisionprofile"
  done
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "dirty tree; commit first"

  echo "== build (Quick Look only)"
  BUILT="$(SKIN_CSS= NO_INSTALL=1 bash "$ROOT/integrations/build-safari.sh" | tail -1)"
  [[ -d "$BUILT" ]] || die "build did not report an app path"
  mkdir -p "$MDIST"
  rsync -a --delete "$BUILT" "$MDIST/"
  APP="$MDIST/$APP_NAME"
  APPEX="$APP/Contents/PlugIns/SpacedownQL.appex"

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

# --- preconditions ------------------------------------------------------------
[[ -n "$VERSION" ]] || die "no version given and none found in project.yml"
has "$(security find-identity -v -p codesigning)" "\"$SIGN_ID\"" \
  || die "signing identity missing: $SIGN_ID"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$NOTARY_PROFILE' missing; run: xcrun notarytool store-credentials $NOTARY_PROFILE"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "dirty tree; commit first"

# --- build + sign ---------------------------------------------------------------
echo "== build + sign ($SIGN_ID)"
# SKIN_CSS is blanked so a personal skin set in the shell never ships in a release.
BUILT="$(SKIN_CSS= SIGN_ID="$SIGN_ID" NO_INSTALL=1 bash "$ROOT/integrations/build-safari.sh" | tail -1)"
[[ -d "$BUILT" ]] || die "build did not report an app path"
mkdir -p "$DIST"
rsync -a --delete "$BUILT" "$DIST/"
APP="$DIST/$APP_NAME"
has "$(codesign -dvv "$APP" 2>&1)" "Authority=Developer ID Application" \
  || die "app is not signed with a Developer ID Application identity"

# --- notarize + staple ----------------------------------------------------------
echo "== notarize"
ditto -c -k --keepParent "$APP" "$DIST/submit.zip"
RESULT="$(xcrun notarytool submit "$DIST/submit.zip" --keychain-profile "$NOTARY_PROFILE" \
  --wait --output-format json)"
STATUS="$(printf '%s' "$RESULT" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
  SUB_ID="$(printf '%s' "$RESULT" | /usr/bin/plutil -extract id raw -o - - 2>/dev/null || true)"
  [[ -n "$SUB_ID" ]] && xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
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

# --- github release -------------------------------------------------------------
[[ "$PUBLISH" == "1" ]] || { echo "release: PUBLISH=0, stopping before the GitHub release"; exit 0; }
DRAFT_FLAG=()
[[ "$DRAFT" == "1" ]] && DRAFT_FLAG=(--draft)
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "release $TAG already exists on $REPO"
fi
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Spacedown $VERSION" \
  --notes "Quick Look preview for Markdown on macOS 13 and later. Unzip, move Spacedown.app to Applications, open it once, then press space on any .md file in Finder.

sha256: \`$SHA\`" ${DRAFT_FLAG[@]+"${DRAFT_FLAG[@]}"}
echo "done: $TAG on $REPO"
