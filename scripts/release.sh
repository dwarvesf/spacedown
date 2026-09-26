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
#   REPO=dwarvesf/md-preview
#   DRAFT=0                 1 = create the release as a draft
#   PUBLISH=1               0 = stop after the notarized zip, no GitHub release
#
# Usage: scripts/release.sh [x.y.z]   (default: MARKETING_VERSION in quick-look/project.yml)
set -euo pipefail

TEAM_ID="${TEAM_ID:-W777S7V8TN}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Dwarves Foundation Company Limited ($TEAM_ID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-DWARVES_NOTARY}"
REPO="${REPO:-dwarvesf/md-preview}"
DRAFT="${DRAFT:-0}"
PUBLISH="${PUBLISH:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$ROOT/integrations/safari/quick-look/project.yml")}"
TAG="v$VERSION"
DIST="$ROOT/build/release/$VERSION"
APP_NAME="Markdown Preview.app"
ZIP="$DIST/Markdown-Preview-$VERSION-macos.zip"

die() { echo "release: $*" >&2; exit 1; }

# --- preconditions ------------------------------------------------------------
[[ -n "$VERSION" ]] || die "no version given and none found in project.yml"
security find-identity -v -p codesigning | grep -qF "\"$SIGN_ID\"" \
  || die "signing identity missing: $SIGN_ID"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$NOTARY_PROFILE' missing; run: xcrun notarytool store-credentials $NOTARY_PROFILE"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "dirty tree; commit first"

# --- build + sign ---------------------------------------------------------------
echo "== build + sign ($SIGN_ID)"
BUILT="$(SIGN_ID="$SIGN_ID" NO_INSTALL=1 bash "$ROOT/integrations/build-safari.sh" | tail -1)"
[[ -d "$BUILT" ]] || die "build did not report an app path"
mkdir -p "$DIST"
rsync -a --delete "$BUILT" "$DIST/"
APP="$DIST/$APP_NAME"
codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application" \
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
spctl -a -vv -t exec "$APP" 2>&1 | grep -q "source=Notarized Developer ID" \
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
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Markdown Preview $VERSION" \
  --notes "Quick Look preview for Markdown on macOS 13 and later. Unzip, move Markdown Preview.app to Applications, open it once, then press space on any .md file in Finder.

sha256: \`$SHA\`" ${DRAFT_FLAG[@]+"${DRAFT_FLAG[@]}"}
echo "done: $TAG on $REPO"
