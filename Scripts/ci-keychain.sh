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
#
# Optional, needed to archive (see below):
#   DEV_CERTIFICATE_BASE64    base64 of an Apple Development .p12
#   DEV_P12_PASSWORD          its password (defaults to P12_PASSWORD)
#
# Optional, needed to export without Apple minting profiles:
#   PROVISIONING_PROFILES_BASE64  base64 of a tar of .provisionprofile files
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
warn() { printf ' warn: %s\n' "$1" >&2; }
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
# Strip whitespace first: a secret pasted through a browser often picks up
# wrapping or a trailing newline, and macOS's base64 silently decodes such
# input to garbage rather than erroring.
printf '%s' "$BUILD_CERTIFICATE_BASE64" | tr -d '[:space:]' \
    | { base64 -D -o "$CERT_P12" 2>/dev/null || base64 -d > "$CERT_P12"; } \
    || die "could not decode BUILD_CERTIFICATE_BASE64 -- is it valid base64?"

[[ -s "$CERT_P12" ]] || die "decoded certificate is empty"

# macOS base64 exits 0 on malformed input, so a corrupt secret yields a
# plausible-looking file. Verify the decode really produced a PKCS#12 archive:
# without this, corruption surfaces later as "MAC verification failed (wrong
# password?)", which sends you chasing the wrong secret.
if ! openssl pkcs12 -in "$CERT_P12" -nokeys -passin pass:"$P12_PASSWORD" \
        -legacy >/dev/null 2>&1 \
   && ! openssl pkcs12 -in "$CERT_P12" -nokeys -passin pass:"$P12_PASSWORD" \
        >/dev/null 2>&1; then
    # Distinguish a bad container from a bad password by re-testing structure
    # with a deliberately wrong password: a valid .p12 fails on the MAC, while
    # a corrupt file fails to parse at all.
    probe="$(openssl pkcs12 -in "$CERT_P12" -nokeys \
             -passin pass:__definitely_not_the_password__ 2>&1 || true)"
    if printf '%s' "$probe" | grep -qiE 'mac verify|invalid password|verification failure'; then
        die "the .p12 decoded correctly but P12_PASSWORD is wrong.
    That is the password you typed when exporting from Keychain Access --
    not your Mac login and not your Apple ID password."
    fi
    die "BUILD_CERTIFICATE_BASE64 did not decode to a valid PKCS#12 archive
    (decoded $(wc -c < "$CERT_P12" | tr -d ' ') bytes).

    Re-export and re-upload, avoiding any copy-paste step:
      base64 -i Certificates.p12 -o cert.b64
      gh secret set BUILD_CERTIFICATE_BASE64 < cert.b64"
fi
info "decoded a valid PKCS#12 archive ($(wc -c < "$CERT_P12" | tr -d ' ') bytes)"

# The project's Release configuration signs with "Apple Development" and only
# the *export* step re-signs with Developer ID, so archiving needs that second
# certificate as well. Without it xcodebuild fails with "No Accounts" and
# "no Mac App Development provisioning profiles".
import_extra_cert() {
    local b64="$1" pw="$2" label="$3" tmp
    tmp="$(mktemp -t automount-devcert).p12"
    printf '%s' "$b64" | tr -d '[:space:]' \
        | { base64 -D -o "$tmp" 2>/dev/null || base64 -d > "$tmp"; } \
        || { rm -f "$tmp"; die "could not decode ${label}"; }
    openssl pkcs12 -in "$tmp" -nokeys -passin pass:"$pw" -legacy >/dev/null 2>&1 \
        || openssl pkcs12 -in "$tmp" -nokeys -passin pass:"$pw" >/dev/null 2>&1 \
        || { rm -f "$tmp"; die "${label} is not a valid PKCS#12 archive, or its password is wrong"; }
    security import "$tmp" -k "$KEYCHAIN_PATH" -P "$pw" \
        -A -T /usr/bin/codesign -T /usr/bin/security \
        || { rm -f "$tmp"; die "failed to import ${label}"; }
    rm -f "$tmp"
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    info "imported ${label}"
}

if [[ -n "${DEV_CERTIFICATE_BASE64:-}" ]]; then
    step "Importing the Apple Development certificate"
    import_extra_cert "$DEV_CERTIFICATE_BASE64" \
        "${DEV_P12_PASSWORD:-$P12_PASSWORD}" "Apple Development certificate"
else
    warn "no DEV_CERTIFICATE_BASE64 set -- archiving will fail unless the
    project's Release configuration signs with Developer ID directly."
fi

# -T codesign grants codesign access without a UI prompt.
security import "$CERT_P12" \
    -k "$KEYCHAIN_PATH" \
    -P "$P12_PASSWORD" \
    -A -T /usr/bin/codesign -T /usr/bin/security \
    || die "failed to import the certificate into the keychain.
    The archive and password are both valid, so this is likely a keychain
    permissions problem on the runner."

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

# ------------------------------------------------------ provisioning profiles

# Free and personal teams cannot create Developer ID profiles through the API
# ("Team ... does not have permission to create Developer ID provisioning
# profiles"), so exporting on a runner needs the profiles Xcode already made on
# a developer's machine. Installing them here lets -exportArchive find them
# instead of trying to mint new ones.
if [[ -n "${PROVISIONING_PROFILES_BASE64:-}" ]]; then
    step "Installing provisioning profiles"
    PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILE_DIR"
    prof_tar="$(mktemp -t automount-profiles).tgz"
    printf '%s' "$PROVISIONING_PROFILES_BASE64" | tr -d '[:space:]' \
        | { base64 -D -o "$prof_tar" 2>/dev/null || base64 -d > "$prof_tar"; } \
        || die "could not decode PROVISIONING_PROFILES_BASE64"
    # -z where gzipped (what export-profiles.sh writes), plain tar otherwise.
    tar -xzf "$prof_tar" -C "$PROFILE_DIR" 2>/dev/null \
        || tar -xf "$prof_tar" -C "$PROFILE_DIR" \
        || die "PROVISIONING_PROFILES_BASE64 did not decode to a tar archive"
    rm -f "$prof_tar"

    # Xcode also reads this location, and -exportArchive prefers it.
    XC_PROFILE_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
    mkdir -p "$XC_PROFILE_DIR"
    cp "$PROFILE_DIR"/*.provisionprofile "$XC_PROFILE_DIR"/ 2>/dev/null || true

    installed=0
    for prof in "$PROFILE_DIR"/*.provisionprofile; do
        [[ -f "$prof" ]] || continue
        name="$(security cms -D -i "$prof" 2>/dev/null \
                | plutil -extract Name raw - -o - 2>/dev/null || echo '?')"
        info "installed: ${name}"
        installed=$(( installed + 1 ))
    done
    (( installed > 0 )) || die "no .provisionprofile files found in the archive"

    # Tell build-release.sh to reuse these rather than ask Apple for new ones.
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "AUTOMOUNT_USE_INSTALLED_PROFILES=1" >> "$GITHUB_ENV"
        info "export will reuse these profiles instead of creating any"
    fi
else
    warn "no PROVISIONING_PROFILES_BASE64 set -- export will ask Apple to create
    Developer ID profiles, which personal teams are not permitted to do."
fi

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

    # xcodebuild needs the same key to create provisioning profiles: a runner
    # has no Xcode account, so -allowProvisioningUpdates otherwise fails with
    # "No Accounts: Add a new account in Accounts settings". Hand the values to
    # build-release.sh, which passes them as -authenticationKey* arguments.
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        {
            echo "AUTOMOUNT_ASC_KEY_PATH=${ASC_KEY_PATH}"
            echo "AUTOMOUNT_ASC_KEY_ID=${ASC_KEY_ID}"
            echo "AUTOMOUNT_ASC_ISSUER_ID=${ASC_ISSUER_ID}"
        } >> "$GITHUB_ENV"
        info "exported provisioning credentials for the build step"
    fi
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
