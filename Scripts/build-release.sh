#!/bin/bash
#
# build-release.sh -- produce a notarized, stapled AutoMount.app inside a DMG.
#
# Builds Release, signs with Developer ID (hardened runtime, unsandboxed),
# notarizes with Apple, staples both the app and the disk image, and emits a
# compressed DMG with an /Applications symlink for drag-install.
#
# Usage:
#   ./Scripts/build-release.sh                      # full release build
#   ./Scripts/build-release.sh --version 1.2.0      # set marketing version
#   ./Scripts/build-release.sh --skip-notarize      # fast local check
#
# Signing is not hardcoded. The team ID and identity are read from the
# Developer ID certificate in your keychain; override either one with
# AUTOMOUNT_TEAM_ID / AUTOMOUNT_SIGN_IDENTITY, or put them in the untracked
# file Scripts/signing.env.
#
# First run requires stored notary credentials:
#   xcrun notarytool store-credentials "AutoMountNotary" \
#       --apple-id "<your-apple-id>" --team-id "<your-team-id>" \
#       --password "<app-specific-password>"
#
set -euo pipefail

# ---------------------------------------------------------------- configuration

# Signing is account-specific and deliberately not hardcoded, so this repo can
# be built by anyone with their own Developer ID. TEAM_ID comes from the
# environment, else Scripts/signing.env (gitignored), else the Developer ID
# certificate in the keychain -- see resolve_signing() below.
TEAM_ID="${AUTOMOUNT_TEAM_ID:-}"
SIGN_IDENTITY="${AUTOMOUNT_SIGN_IDENTITY:-}"
readonly SCHEME="AutoMount"
readonly APP_NAME="AutoMount"
readonly VOLNAME="AutoMount"
readonly BUNDLE_ID="org.tassinari.AutoMount"
readonly LOGIN_ITEM_ID="org.tassinari.AutoMount.AutoMountBackground"
readonly APP_GROUP="group.org.tassinari.automount"

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT="${REPO_ROOT}/${APP_NAME}.xcodeproj"
readonly EXPORT_TEMPLATE="${REPO_ROOT}/Scripts/ExportOptions.plist"
readonly SIGNING_ENV="${REPO_ROOT}/Scripts/signing.env"
readonly BUILD_DIR="${REPO_ROOT}/build"

VERSION="1.0"
BUILD_NUM=""
OUTPUT_DIR="${REPO_ROOT}/dist"
KEYCHAIN_PROFILE="AutoMountNotary"
SKIP_NOTARIZE=0
SKIP_TESTS=0

# ---------------------------------------------------------------------- output

if [[ -t 1 ]]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
    RED=""; GRN=""; YEL=""; BLD=""; RST=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$GRN" "$RST" "$BLD" "$1" "$RST"; }
info() { printf '    %s\n' "$1"; }
warn() { printf '%s warn:%s %s\n' "$YEL" "$RST" "$1" >&2; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }

# --------------------------------------------------------------------- cleanup

MOUNT_DEV=""
STAGE_DIR=""
EXPORT_PLIST=""
EXPORT_TMPDIR=""
cleanup() {
    if [[ -n "$MOUNT_DEV" ]]; then
        hdiutil detach "$MOUNT_DEV" -quiet 2>/dev/null || true
    fi
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR"
    fi
    if [[ -n "$EXPORT_TMPDIR" && -d "$EXPORT_TMPDIR" ]]; then
        rm -rf "$EXPORT_TMPDIR"
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------------- arguments

usage() {
    sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)          VERSION="${2:?--version needs a value}"; shift 2 ;;
        --build)            BUILD_NUM="${2:?--build needs a value}"; shift 2 ;;
        --output)           OUTPUT_DIR="${2:?--output needs a value}"; shift 2 ;;
        --keychain-profile) KEYCHAIN_PROFILE="${2:?--keychain-profile needs a value}"; shift 2 ;;
        --skip-notarize)    SKIP_NOTARIZE=1; shift ;;
        --skip-tests)       SKIP_TESTS=1; shift ;;
        -h|--help)          usage ;;
        *)                  die "unknown option: $1 (try --help)" ;;
    esac
done

# Default build number to the commit count, so every release is distinguishable.
if [[ -z "$BUILD_NUM" ]]; then
    BUILD_NUM="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
fi

readonly ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
readonly EXPORT_DIR="${BUILD_DIR}/export"
readonly APP="${EXPORT_DIR}/${APP_NAME}.app"
readonly LOGIN_ITEM="${APP}/Contents/Library/LoginItems/AutoMountBackground.app"

if (( SKIP_NOTARIZE )); then
    readonly DMG_FINAL="${OUTPUT_DIR}/${APP_NAME}-${VERSION}-UNNOTARIZED.dmg"
else
    readonly DMG_FINAL="${OUTPUT_DIR}/${APP_NAME}-${VERSION}.dmg"
fi

# ------------------------------------------------------- phase 1: preflight

step "Preflight"

[[ -d "$PROJECT" ]]          || die "project not found: $PROJECT"
[[ -f "$EXPORT_TEMPLATE" ]]  || die "export template not found: $EXPORT_TEMPLATE"

command -v xcodebuild >/dev/null || die "xcodebuild not found -- install Xcode"

# The Developer ID cert must be present, or the export silently falls back to
# a development identity that cannot be notarized. Its common name also carries
# the team ID in trailing parens, which is where we read signing config from
# when the environment does not supply it.
#
#   Developer ID Application: Some Name (ABCDE12345)
#
resolve_signing() {
    # Optional untracked file for developers who prefer not to export vars.
    if [[ -f "$SIGNING_ENV" ]]; then
        # shellcheck source=/dev/null
        source "$SIGNING_ENV"
        TEAM_ID="${AUTOMOUNT_TEAM_ID:-$TEAM_ID}"
        SIGN_IDENTITY="${AUTOMOUNT_SIGN_IDENTITY:-$SIGN_IDENTITY}"
    fi

    local found
    found="$(security find-identity -v -p codesigning 2>/dev/null \
             | grep -F "Developer ID Application" || true)"

    if [[ -z "$found" ]]; then
        die "no 'Developer ID Application' identity in the keychain.
    Download it from https://developer.apple.com/account/resources/certificates
    or via Xcode > Settings > Accounts > Manage Certificates."
    fi

    if [[ -z "$SIGN_IDENTITY" ]]; then
        local count
        count="$(printf '%s\n' "$found" | grep -c .)"
        if (( count > 1 )); then
            die "multiple 'Developer ID Application' identities in the keychain:
$(printf '%s\n' "$found" | sed 's/^/    /')

    Pick one by exporting its full common name, e.g.
      export AUTOMOUNT_SIGN_IDENTITY='Developer ID Application: Your Name (ABCDE12345)'"
        fi
        # Common name sits between the first quote pair on the line.
        SIGN_IDENTITY="$(printf '%s\n' "$found" | sed -n 's/.*"\(.*\)".*/\1/p')"
        [[ -n "$SIGN_IDENTITY" ]] \
            || die "could not parse the signing identity from:\n${found}"
    fi

    if [[ -z "$TEAM_ID" ]]; then
        # Trailing (TEAMID) of the common name.
        TEAM_ID="$(printf '%s\n' "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
        [[ -n "$TEAM_ID" ]] \
            || die "could not derive a team ID from signing identity '${SIGN_IDENTITY}'.
    Set it explicitly:  export AUTOMOUNT_TEAM_ID=ABCDE12345"
    fi

    readonly TEAM_ID SIGN_IDENTITY
}

resolve_signing
info "signing identity: ${SIGN_IDENTITY}"
info "team id: ${TEAM_ID}"

# xcodebuild can only create provisioning profiles when it has an authenticated
# account. On a developer's Mac that comes from Xcode > Settings > Accounts; on
# a runner there is none, and -allowProvisioningUpdates fails with "No Accounts:
# Add a new account in Accounts settings". An App Store Connect API key supplies
# that identity headlessly. Set AUTOMOUNT_ASC_* (the CI keychain script exports
# them) to enable it; without them these stay empty and behaviour is unchanged.
# The archive and the export need opposite treatment.
#
# The archive signs with "Apple Development" and wants a Mac Team Provisioning
# Profile. Those are device-bound, so they cannot be shipped from a developer's
# machine -- but Apple *does* permit creating them, so the archive keeps
# -allowProvisioningUpdates and mints one for the runner.
#
# The export signs with Developer ID and wants a "Direct" profile. A personal
# team may not create those ("Team ... does not have permission to create
# Developer ID provisioning profiles"), so the export must reuse the profiles
# installed from PROVISIONING_PROFILES_BASE64 and must NOT pass the flag --
# passing it makes xcodebuild try to create one and fail.
ARCHIVE_PROVISION_ARGS=(-allowProvisioningUpdates)
EXPORT_PROVISION_ARGS=(-allowProvisioningUpdates)
if [[ "${AUTOMOUNT_USE_INSTALLED_PROFILES:-0}" == "1" ]]; then
    EXPORT_PROVISION_ARGS=()
    info "export will reuse pre-installed profiles (no Developer ID creation)"
fi

AUTH_ARGS=()
if [[ -n "${AUTOMOUNT_ASC_KEY_PATH:-}" && -n "${AUTOMOUNT_ASC_KEY_ID:-}" \
      && -n "${AUTOMOUNT_ASC_ISSUER_ID:-}" ]]; then
    [[ -f "$AUTOMOUNT_ASC_KEY_PATH" ]] \
        || die "App Store Connect key not found at ${AUTOMOUNT_ASC_KEY_PATH}"
    AUTH_ARGS=(
        -authenticationKeyPath "$AUTOMOUNT_ASC_KEY_PATH"
        -authenticationKeyID "$AUTOMOUNT_ASC_KEY_ID"
        -authenticationKeyIssuerID "$AUTOMOUNT_ASC_ISSUER_ID"
    )
    info "using App Store Connect API key ${AUTOMOUNT_ASC_KEY_ID} for provisioning"
fi

# ExportOptions.plist needs a literal team ID, so generate it from the tracked
# template rather than keeping a developer-specific copy in the repo.
# `mktemp -t` appends its own random suffix, so it cannot produce a name ending
# in .plist; make a temp directory and put a correctly-named file inside it.
EXPORT_TMPDIR="$(mktemp -d -t AutoMountExport)"
EXPORT_PLIST="${EXPORT_TMPDIR}/ExportOptions.plist"
sed "s/__TEAM_ID__/${TEAM_ID}/" "$EXPORT_TEMPLATE" > "$EXPORT_PLIST"
if grep -qF "__TEAM_ID__" "$EXPORT_PLIST"; then
    die "failed to substitute team ID into export options"
fi

# libMounter is vendored in this repo; a missing or empty checkout (a partial
# clone, say) gives an xcodebuild error that is not obvious.
if [[ ! -f "${REPO_ROOT}/Packages/libMounter/Package.swift" ]]; then
    die "vendored package 'libMounter' is missing from Packages/libMounter.
    Expected Packages/libMounter/Package.swift. Re-clone or restore the checkout."
fi

if (( ! SKIP_NOTARIZE )); then
    if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
        die "no stored notary credentials for profile '${KEYCHAIN_PROFILE}'.
    Create them once with:

      xcrun notarytool store-credentials \"${KEYCHAIN_PROFILE}\" \\
          --apple-id \"<your-apple-id>\" \\
          --team-id \"${TEAM_ID}\" \\
          --password \"<app-specific-password>\"

    Generate an app-specific password at https://appleid.apple.com (Sign-In and
    Security > App-Specific Passwords). Or re-run with --skip-notarize to
    produce an unnotarized build for local testing."
    fi
    info "notary profile:   ${KEYCHAIN_PROFILE}"
else
    warn "--skip-notarize: output will NOT be distributable"
fi

info "version:          ${VERSION} (build ${BUILD_NUM})"
info "output:           ${DMG_FINAL}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# ----------------------------------------------------------- phase 2: tests

if (( SKIP_TESTS )); then
    warn "--skip-tests: skipping test suites"
else
    step "Running tests"
    # Unit tests only. The UI tests are deliberately excluded: they drive a real
    # app instance, which makes them slow and flaky in a release build, and they
    # add nothing the signing verification in phase 5 does not already cover.
    # Run them from Xcode, or with the AutoMount scheme directly.
    for test_target in AutoMountTests AutoMountBackgroundTests; do
        info "testing ${test_target}..."
        xcodebuild test \
            -project "$PROJECT" \
            -scheme "${test_target%Tests}" \
            -destination 'platform=macOS' \
            -only-testing:"$test_target" \
            -quiet \
            || die "tests failed for ${test_target}"
    done
    info "all tests passed"
fi

# --------------------------------------------------------- phase 3: archive

step "Archiving (Release, universal)"

# Version is injected on the command line rather than baked into the project,
# so releases are versioned without dirtying project.pbxproj. This also avoids
# a run-script phase, which would trip over ENABLE_USER_SCRIPT_SANDBOXING.
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    "${ARCHIVE_PROVISION_ARGS[@]+"${ARCHIVE_PROVISION_ARGS[@]}"}" \
    "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}" \
    -quiet \
    || die "archive failed.
    If this says \"No Accounts\" or \"no Mac App Development provisioning
    profiles\", xcodebuild has no account to create profiles with. On a CI
    runner set the App Store Connect API key secrets (ASC_KEY_ID,
    ASC_ISSUER_ID, ASC_KEY_BASE64); a certificate alone is not enough."

[[ -d "$ARCHIVE_PATH" ]] || die "archive missing at $ARCHIVE_PATH"
info "archived to ${ARCHIVE_PATH#$REPO_ROOT/}"

# ---------------------------------------------------------- phase 4: export

step "Exporting with Developer ID signature"

# -exportArchive re-signs the whole bundle hierarchy inside-out and embeds a
# distinct provisioning profile per bundle ID. Doing this by hand with codesign
# is what usually breaks the nested login item's entitlements.
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_DIR" \
    "${EXPORT_PROVISION_ARGS[@]+"${EXPORT_PROVISION_ARGS[@]}"}" \
    "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}" \
    -quiet \
    || die "export failed -- see the log above.
    If this is a provisioning failure, the app group entitlement (${APP_GROUP})
    needs Developer ID profiles for both ${BUNDLE_ID} and ${LOGIN_ITEM_ID}."

[[ -d "$APP" ]] || die "exported app missing at $APP"
info "exported ${APP#$REPO_ROOT/}"

# ---------------------------------------------------- phase 5: verification

step "Verifying signature and entitlements"

[[ -d "$LOGIN_ITEM" ]] || die "login item missing at Contents/Library/LoginItems"

# Regression guard for the duplicate embed that used to ship in Resources.
if [[ -e "${APP}/Contents/Resources/AutoMountBackground.app" ]]; then
    die "duplicate AutoMountBackground.app found in Contents/Resources.
    The Resources copy build phase has regressed in project.pbxproj."
fi

# --deep is correct for verification (walk all nested code); it is only
# harmful when signing, where it would flatten per-bundle entitlements.
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /' \
    || die "signature verification failed"

# Anything landing in Frameworks would need its own signature; libMounter is
# expected to link statically.
if [[ -d "${APP}/Contents/Frameworks" ]] && [[ -n "$(ls -A "${APP}/Contents/Frameworks" 2>/dev/null)" ]]; then
    warn "Contents/Frameworks is non-empty -- these need separate signing:"
    ls -1 "${APP}/Contents/Frameworks" | sed 's/^/      /'
fi

for bundle in "$APP" "$LOGIN_ITEM"; do
    name="$(basename "$bundle")"

    # Capture once and assert against the copy. Calling `codesign -d` repeatedly
    # in quick succession on the same bundle intermittently yields empty output,
    # which reads as a missing flag and fails an otherwise valid build.
    sig_info="$(codesign -d --verbose=2 "$bundle" 2>&1)" \
        || die "could not read the signature of ${name}"
    entitlements="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null || true)"

    # Hardened runtime is mandatory for notarization.
    printf '%s' "$sig_info" | grep -q 'flags=.*runtime' \
        || die "hardened runtime not enabled on ${name}"

    # The app group is the only IPC channel between the two apps, and losing it
    # fails silently at runtime (UserDefaults falls back to .standard), so it is
    # asserted rather than assumed.
    printf '%s' "$entitlements" | grep -qF "$APP_GROUP" \
        || die "app group '${APP_GROUP}' missing from ${name}.
    The two apps would launch normally but silently stop sharing state."

    # The app group entitlement is profile-backed on macOS.
    [[ -f "${bundle}/Contents/embedded.provisionprofile" ]] \
        || die "no embedded provisioning profile in ${name}"

    printf '%s' "$sig_info" | grep -qF "Authority=Developer ID Application" \
        || die "${name} is not signed with a Developer ID Application certificate"

    info "${name}: hardened runtime, app group, profile, Developer ID -- ok"
done

# Informational only: Gatekeeper correctly rejects until the ticket is stapled.
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /' || true

# ------------------------------------------------------ phase 6: notarize app

if (( ! SKIP_NOTARIZE )); then
    step "Notarizing app"

    ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"
    # ditto, not zip: zip mangles symlinks and resource forks in app bundles.
    ditto -c -k --keepParent "$APP" "$ZIP_PATH"

    NOTARY_JSON="${BUILD_DIR}/notary-app.json"
    if ! xcrun notarytool submit "$ZIP_PATH" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait --timeout 30m \
            --output-format json > "$NOTARY_JSON" 2>&1; then
        cat "$NOTARY_JSON" >&2
        die "notarization submission failed"
    fi

    STATUS="$(plutil -extract status raw -o - "$NOTARY_JSON" 2>/dev/null || echo unknown)"
    SUB_ID="$(plutil -extract id raw -o - "$NOTARY_JSON" 2>/dev/null || echo "")"
    info "submission ${SUB_ID}: ${STATUS}"

    if [[ "$STATUS" != "Accepted" ]]; then
        warn "notarization was not accepted -- fetching the log:"
        [[ -n "$SUB_ID" ]] && xcrun notarytool log "$SUB_ID" \
            --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | sed 's/^/    /' || true
        die "notarization failed with status: ${STATUS}"
    fi

    # ------------------------------------------------- phase 7: staple app
    step "Stapling app"
    # Stapling the .app makes it validate offline forever once installed.
    xcrun stapler staple "$APP"  || die "failed to staple the app"
    xcrun stapler validate "$APP" || die "staple validation failed for the app"
    info "ticket stapled to ${APP_NAME}.app"
fi

# ------------------------------------------------------------ phase 8: dmg

step "Building DMG"

STAGE_DIR="$(mktemp -d)"
cp -R "$APP" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"   # drag-to-install target

DMG_RW="${BUILD_DIR}/rw.dmg"
# HFS+ rather than APFS: APFS images will not mount on older macOS, and the
# app's deployment target is 14.6.
hdiutil create -srcfolder "$STAGE_DIR" -volname "$VOLNAME" \
    -fs HFS+ -format UDRW -ov "$DMG_RW" -quiet \
    || die "failed to create the disk image"

rm -f "$DMG_FINAL"
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 \
    -ov -o "$DMG_FINAL" -quiet \
    || die "failed to compress the disk image"

rm -rf "$STAGE_DIR"; STAGE_DIR=""
info "created ${DMG_FINAL#$REPO_ROOT/}"

# ------------------------------------------- phase 9: sign/notarize/staple dmg

step "Signing DMG"
# A disk image is not executable code, so no --options runtime and no
# entitlements here; those apply to the app bundles only.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_FINAL" \
    || die "failed to sign the disk image"

if (( ! SKIP_NOTARIZE )); then
    step "Notarizing DMG"
    # A second ticket: stapling the DMG lets Gatekeeper clear it at mount time,
    # offline. The app's own ticket does not cover the image itself.
    NOTARY_DMG_JSON="${BUILD_DIR}/notary-dmg.json"
    if ! xcrun notarytool submit "$DMG_FINAL" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait --timeout 30m \
            --output-format json > "$NOTARY_DMG_JSON" 2>&1; then
        cat "$NOTARY_DMG_JSON" >&2
        die "DMG notarization submission failed"
    fi

    STATUS="$(plutil -extract status raw -o - "$NOTARY_DMG_JSON" 2>/dev/null || echo unknown)"
    SUB_ID="$(plutil -extract id raw -o - "$NOTARY_DMG_JSON" 2>/dev/null || echo "")"
    info "submission ${SUB_ID}: ${STATUS}"

    if [[ "$STATUS" != "Accepted" ]]; then
        warn "DMG notarization was not accepted -- fetching the log:"
        [[ -n "$SUB_ID" ]] && xcrun notarytool log "$SUB_ID" \
            --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | sed 's/^/    /' || true
        die "DMG notarization failed with status: ${STATUS}"
    fi

    step "Stapling DMG"
    xcrun stapler staple "$DMG_FINAL" || die "failed to staple the disk image"

    # ------------------------------------------------- phase 10: final gate
    step "Final verification"
    xcrun stapler validate "$DMG_FINAL" || die "staple validation failed for the DMG"

    # Assess type differs by artifact: -t exec for .app, -t open for .dmg.
    spctl -a -vvv -t open --context context:primary-signature "$DMG_FINAL" 2>&1 \
        | sed 's/^/    /' \
        || die "Gatekeeper rejected the disk image"
fi

# ---------------------------------------------------------------------- done

DMG_SIZE="$(du -h "$DMG_FINAL" | cut -f1 | tr -d ' ')"
printf '\n%s==>%s %sDone%s\n' "$GRN" "$RST" "$BLD" "$RST"
info "${DMG_FINAL}"
info "${DMG_SIZE}, version ${VERSION} (build ${BUILD_NUM})"

if (( SKIP_NOTARIZE )); then
    printf '\n%s%s%s\n' "$YEL" \
        "This build is NOT notarized and will be blocked by Gatekeeper. Local testing only." "$RST"
else
    info "notarized and stapled -- ready to distribute"
fi
