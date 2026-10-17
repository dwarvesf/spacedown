# notary-auth.sh: sourced by build-safari.sh. notary_auth fills the NOTARY_AUTH array
# with the notarytool credential flags, the same choice scripts/release.sh makes: an App
# Store Connect API key when NOTARY_KEY (a .p8 path) is set, which then needs NOTARY_KEY_ID
# and NOTARY_ISSUER, else the keychain profile named by NOTARIZE.
notary_auth() {
  if [[ -n "${NOTARY_KEY:-}" ]]; then
    NOTARY_AUTH=( --key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID unset}" --issuer "${NOTARY_ISSUER:?NOTARY_ISSUER unset}" )
  else
    NOTARY_AUTH=( --keychain-profile "${NOTARIZE:?NOTARIZE profile unset}" )
  fi
}
