#!/bin/bash
# Run altool (validate or upload) for the Spacedown pkg with the team's App Store Connect API
# key read from 1Password. The key file lives in a 700 temp dir for the call only.
# Usage: mas-altool.sh [--dry-run] validate|upload <pkg>
#   --dry-run  check the arguments and the settings below, then stop: no 1Password read,
#              no altool call.
# Env (required, no defaults):
#   OP_VAULT     the 1Password vault that holds the API key item
#   ASC_OP_ITEM  the API key item's title, or the end of it; the item has the fields
#                "Key ID", "Issuer ID" and "Private Key (.p8 PEM)"
set -euo pipefail
usage() { echo "usage: mas-altool.sh [--dry-run] validate|upload <pkg>" >&2; exit 64; }
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; shift; fi
[[ $# -eq 2 ]] || usage
MODE="$1"; PKG="$2"
case "$MODE" in validate|upload) ;; *) usage ;; esac
[[ -f "$PKG" ]] || { echo "mas-altool: no such package: $PKG" >&2; exit 1; }
VAULT="${OP_VAULT:?OP_VAULT unset: name the 1Password vault that holds the App Store Connect API key}"
ITEM="${ASC_OP_ITEM:?ASC_OP_ITEM unset: name the 1Password item (title or its end) that holds the API key}"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run: $MODE $PKG with the API key item ending \"$ITEM\" in vault \"$VAULT\"; nothing read or uploaded"
  exit 0
fi
WORK="$(mktemp -d)"; chmod 700 "$WORK"; trap 'rm -rf "$WORK"' EXIT
ID="$(op item list --vault "$VAULT" --format json | jq -r --arg t "$ITEM" 'map(select(.title | endswith($t)))[0].id // empty')"
[[ -n "$ID" ]] || { echo "mas-altool: no item ending \"$ITEM\" in vault \"$VAULT\"" >&2; exit 1; }
op item get "$ID" --vault "$VAULT" --format json >| "$WORK/item.json"
KEY_ID="$(jq -r '.fields[] | select(.label == "Key ID") | .value' "$WORK/item.json")"
ISSUER="$(jq -r '.fields[] | select(.label == "Issuer ID") | .value' "$WORK/item.json")"
jq -r '.fields[] | select(.label == "Private Key (.p8 PEM)") | .value' "$WORK/item.json" >| "$WORK/AuthKey_${KEY_ID}.p8"
rm -f "$WORK/item.json"
export API_PRIVATE_KEYS_DIR="$WORK"
case "$MODE" in
  validate) xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | grep -v -i -E 'apiKey|issuer' | tail -15 ;;
  upload)   xcrun altool --upload-app   -f "$PKG" -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | grep -v -i -E 'apiKey|issuer' | tail -15 ;;
esac
