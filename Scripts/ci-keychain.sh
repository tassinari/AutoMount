#!/bin/bash
#
# ci-keychain.sh -- bootstrap signing credentials on an ephemeral CI runner.
#
# build-release.sh reads its signing material from the local keychain and its
# notary credentials from a stored notarytool profile. A fresh runner has
# neither, so this script builds both from repository secrets, then gets out of
# the way: build-release.sh runs unmodified afterwards and resolves signing
# exactly as it does on a developer's machine.
#
# Usage:
#   ./Scripts/ci-keychain.sh            # set up (expects the env vars below)
#   ./Scripts/ci-keychain.sh --cleanup  # delete the keychain and API key
#
# Required environment:
#   BUILD_CERTIFICATE_BASE64  base64 of the Developer ID Application .p12
#   P12_PASSWORD              password the .p12 was exported with
#   KEYCHAIN_PASSWORD         any random string; secures the temp keychain
#   APPLE_ID                  Apple ID email, for notarization
#   APPLE_TEAM_ID             10-character team ID
#   APPLE_APP_PASSWORD        app-specific password from appleid.apple.com
#
# Optional, for App Store Connect API authentication instead of Apple ID:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_BASE64
#
# This script is intended for CI. It creates a keychain with a known password
# and is not something to run on a machine you care about.
#
set -euo pipefail

readonly KEYCHAIN_NAME="automount-ci.keychain-db"
readonly KEYCHAIN_PATH="${HOME}/Library/Keychains/${KEYCHAIN_NAME}"
readonly NOTARY_PROFILE="${AUTOMOUNT_NOTARY_PROFILE:-AutoMountNotary}"
readonly ASC_KEY_DIR="${HOME}/.appstoreconnect/private_keys"

step() { printf '\n==> %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
die()  { printf '\nerror: %s\n' "$1" >&2; exit 1; }

# ------------------------------------------------------------------- cleanup

if [[ "${1:-}" == "--cleanup" ]]; then
    step "Removing CI signing credentials"
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null \
        && info "deleted ${KEYCHAIN_NAME}" \
        || info "no keychain to delete"
    rm -rf "$ASC_KEY_DIR" 2>/dev/null || true
    info "removed any App Store Connect key"
    exit 0
fi

# -------------------------------------------------------------- preflight

require() {
    [[ -n "${!1:-}" ]] || die "missing required environment variable: $1
    Set it as a repository secret and pass it through in the workflow's env."
}
for v in BUILD_CERTIFICATE_BASE64 P12_PASSWORD KEYCHAIN_PASSWORD APPLE_TEAM_ID; do
    require "$v"
done

# Notarization needs either an App Store Connect API key or an Apple ID with an
# app-specific password. Prefer the API key: it does not expire on password
# change and carries no 2FA interaction.
USE_ASC_KEY=0
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_BASE64:-}" ]]; then
    USE_ASC_KEY=1
else
    for v in APPLE_ID APPLE_APP_PASSWORD; do
        require "$v"
    done
fi

# ----------------------------------------------------------- keychain setup

step "Creating a temporary keychain"

# Start clean: a re-run on a warm runner must not stack duplicate identities.
security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
# Without this the keychain relocks mid-build and codesign fails partway.
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
info "created ${KEYCHAIN_NAME}"

# Put it in the search list, keeping the login keychain so system roots resolve.
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')
security default-keychain -s "$KEYCHAIN_PATH"
info "set as default keychain"

step "Importing the Developer ID certificate"

CERT_P12="$(mktemp -t automount-cert).p12"
cleanup_cert() { rm -f "$CERT_P12"; }
trap cleanup_cert EXIT

# base64 -D on macOS, -d on GNU; accept either so this runs locally too.
printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 -D -o "$CERT_P12" 2>/dev/null \
    || printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 -d > "$CERT_P12" \
    || die "could not decode BUILD_CERTIFICATE_BASE64 -- is it valid base64?"

[[ -s "$CERT_P12" ]] || die "decoded certificate is empty"

# -T codesign grants codesign access without a UI prompt.
security import "$CERT_P12" \
    -k "$KEYCHAIN_PATH" \
    -P "$P12_PASSWORD" \
    -A -T /usr/bin/codesign -T /usr/bin/security \
    || die "failed to import the certificate -- is P12_PASSWORD correct?"

# Without a partition list, codesign blocks on a GUI authorization prompt that
# never comes on a headless runner, and the build hangs until it times out.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null 2>&1 \
    || die "failed to set the key partition list"

info "imported and authorized for codesign"

# Prove the identity resolves the same way build-release.sh will find it.
step "Verifying the signing identity"

FOUND="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
         | grep -F "Developer ID Application" || true)"
[[ -n "$FOUND" ]] || die "no 'Developer ID Application' identity after import.
    The .p12 must contain a Developer ID Application certificate *and* its
    private key. Export both from Keychain Access."

printf '%s\n' "$FOUND" | sed 's/^/    /'

IDENT_TEAM="$(printf '%s\n' "$FOUND" \
    | sed -n 's/.*"\(.*\)".*/\1/p' \
    | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' | head -1)"
if [[ -n "$IDENT_TEAM" && "$IDENT_TEAM" != "$APPLE_TEAM_ID" ]]; then
    die "certificate team (${IDENT_TEAM}) does not match APPLE_TEAM_ID (${APPLE_TEAM_ID})."
fi
info "team ${APPLE_TEAM_ID} matches the certificate"

# ------------------------------------------------------- notary credentials

step "Storing notary credentials"

if (( USE_ASC_KEY )); then
    mkdir -p "$ASC_KEY_DIR"
    ASC_KEY_PATH="${ASC_KEY_DIR}/AuthKey_${ASC_KEY_ID}.p8"
    printf '%s' "$ASC_KEY_BASE64" | base64 -D -o "$ASC_KEY_PATH" 2>/dev/null \
        || printf '%s' "$ASC_KEY_BASE64" | base64 -d > "$ASC_KEY_PATH" \
        || die "could not decode ASC_KEY_BASE64"
    chmod 600 "$ASC_KEY_PATH"

    xcrun notarytool store-credentials "$NOTARY_PROFILE" \
        --key "$ASC_KEY_PATH" \
        --key-id "$ASC_KEY_ID" \
        --issuer "$ASC_ISSUER_ID" \
        --keychain "$KEYCHAIN_PATH" \
        || die "failed to store notary credentials from the API key"
    info "stored profile '${NOTARY_PROFILE}' (App Store Connect API key)"
else
    xcrun notarytool store-credentials "$NOTARY_PROFILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --keychain "$KEYCHAIN_PATH" \
        || die "failed to store notary credentials -- check APPLE_ID and
    APPLE_APP_PASSWORD (an app-specific password, not your Apple ID password)."
    info "stored profile '${NOTARY_PROFILE}' (Apple ID)"
fi

# build-release.sh preflights with `notarytool history`; fail here instead,
# where the error message can say which secret is wrong.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
    --keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 \
    || die "stored notary credentials were rejected by Apple.
    Verify APPLE_ID / APPLE_APP_PASSWORD (or the ASC_* key) and APPLE_TEAM_ID."
info "credentials accepted by Apple"

# build-release.sh calls notarytool without --keychain, so it resolves the
# profile from the *default* keychain. That is set above; assert it here rather
# than leaving the coupling implicit, because the failure mode otherwise is a
# confusing "no stored credentials" error 20 minutes into a release build.
DEFAULT_KC="$(security default-keychain | tr -d ' "')"
[[ "$DEFAULT_KC" == "$KEYCHAIN_PATH" ]] \
    || die "default keychain is '${DEFAULT_KC}', expected '${KEYCHAIN_PATH}'.
    build-release.sh reads the notary profile from the default keychain."

step "Ready"
info "keychain: ${KEYCHAIN_PATH}"
info "notary profile: ${NOTARY_PROFILE}"
info "run ./Scripts/build-release.sh next"
