#!/bin/bash
# Run altool (validate or upload) for the Spacedown pkg with the team API key from
# 1Password. The key file lives in a 700 temp dir for the call only.
# Usage: mas-altool.sh validate|upload <pkg>
set -euo pipefail
MODE="$1"; PKG="$2"
VAULT=dfoundation-prod
WORK="$(mktemp -d)"; chmod 700 "$WORK"; trap 'rm -rf "$WORK"' EXIT
ID="$(op item list --vault "$VAULT" --format json | jq -r '.[] | select(.title | test("Hacker Bar Release$")) | .id')"
op item get "$ID" --vault "$VAULT" --format json >| "$WORK/item.json"
KEY_ID="$(jq -r '.fields[] | select(.label == "Key ID") | .value' "$WORK/item.json")"
ISSUER="$(jq -r '.fields[] | select(.label == "Issuer ID") | .value' "$WORK/item.json")"
jq -r '.fields[] | select(.label == "Private Key (.p8 PEM)") | .value' "$WORK/item.json" >| "$WORK/AuthKey_${KEY_ID}.p8"
rm -f "$WORK/item.json"
export API_PRIVATE_KEYS_DIR="$WORK"
case "$MODE" in
  validate) xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | grep -v -i -E 'apiKey|issuer' | tail -15 ;;
  upload)   xcrun altool --upload-app   -f "$PKG" -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | grep -v -i -E 'apiKey|issuer' | tail -15 ;;
  *) echo "usage: mas-altool.sh validate|upload <pkg>" >&2; exit 64 ;;
esac
