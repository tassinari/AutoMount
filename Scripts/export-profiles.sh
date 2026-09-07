#!/bin/bash
#
# export-profiles.sh -- package this machine's AutoMount provisioning profiles
# for CI.
#
# A personal Apple team cannot create "Developer ID" provisioning profiles
# through the App Store Connect API, so a runner cannot mint its own. Xcode has
# already created them locally; this bundles them into a base64 blob to store as
# the PROVISIONING_PROFILES_BASE64 secret.
#
# Usage:
#   ./Scripts/export-profiles.sh              # write profiles.b64
#   ./Scripts/export-profiles.sh --upload     # and set the GitHub secret
#
set -euo pipefail

readonly XC_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
readonly OUT="${PWD}/profiles.b64"
readonly BUNDLE_IDS=("org.tassinari.AutoMount" "org.tassinari.AutoMount.AutoMountBackground")

step() { printf '\n==> %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
die()  { printf '\nerror: %s\n' "$1" >&2; exit 1; }

[[ -d "$XC_DIR" ]] || die "no Xcode provisioning profiles directory.
    Open the project in Xcode and archive once so Xcode creates the profiles."

step "Finding Developer ID profiles for AutoMount"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
found=0

for prof in "$XC_DIR"/*.provisionprofile; do
    [[ -f "$prof" ]] || continue
    plist="$(security cms -D -i "$prof" 2>/dev/null || true)"
    [[ -n "$plist" ]] || continue
    name="$(printf '%s' "$plist" | plutil -extract Name raw - -o - 2>/dev/null || true)"

    # "Direct" profiles are the Developer ID ones; the plain "Team" profiles are
    # for development and are not what a release export needs.
    case "$name" in *"Direct Provisioning Profile"*) ;; *) continue ;; esac

    for bid in "${BUNDLE_IDS[@]}"; do
        case "$name" in
            *"$bid")
                cp "$prof" "$staging/"
                info "$name"
                found=$(( found + 1 ))
                ;;
        esac
    done
done

(( found > 0 )) || die "no matching Developer ID profiles found.
    Archive the app once in Xcode (Product > Archive), then re-run."

step "Packaging"
# gzip: a raw tar of two profiles base64s to ~88KB, over GitHub's 48KB
# secret limit; compressed it is around 22KB.
tar -czf "${staging}.tgz" -C "$staging" .
base64 -i "${staging}.tgz" -o "$OUT"
rm -f "${staging}.tgz"
info "wrote ${OUT} (${found} profile(s), $(wc -c < "$OUT" | tr -d ' ') bytes)"

if [[ "${1:-}" == "--upload" ]]; then
    command -v gh >/dev/null || die "gh CLI not found"
    step "Uploading secret"
    gh secret set PROVISIONING_PROFILES_BASE64 < "$OUT"
    info "set PROVISIONING_PROFILES_BASE64"
else
    step "Next"
    info "gh secret set PROVISIONING_PROFILES_BASE64 < ${OUT}"
fi
