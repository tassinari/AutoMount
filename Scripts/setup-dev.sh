#!/bin/bash
#
# setup-dev.sh -- write Config/Local.xcconfig so this checkout can be built.
#
# The repo does not carry an Apple Developer Team ID (see Config/Signing.xcconfig).
# This script finds yours and writes it to the untracked Config/Local.xcconfig.
#
# Usage:
#   ./Scripts/setup-dev.sh                  # detect the team automatically
#   ./Scripts/setup-dev.sh --team ABCDE12345
#   ./Scripts/setup-dev.sh --force          # overwrite an existing Local.xcconfig
#   ./Scripts/setup-dev.sh --print          # show what was detected, write nothing
#
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOCAL_CONFIG="${REPO_ROOT}/Config/Local.xcconfig"

TEAM_ID=""
FORCE=0
PRINT_ONLY=0

if [[ -t 1 ]]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
    RED=""; GRN=""; YEL=""; BLD=""; RST=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$GRN" "$RST" "$BLD" "$1" "$RST"; }
info() { printf '    %s\n' "$1"; }
warn() { printf '%s warn:%s %s\n' "$YEL" "$RST" "$1" >&2; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }

usage() {
    sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --team)   TEAM_ID="${2:?--team needs a value}"; shift 2 ;;
        --force)  FORCE=1; shift ;;
        --print)  PRINT_ONLY=1; shift ;;
        -h|--help) usage ;;
        *)        die "unknown argument: $1 (try --help)" ;;
    esac
done

# A team ID is exactly 10 uppercase alphanumerics.
valid_team() { [[ "$1" =~ ^[A-Z0-9]{10}$ ]]; }

# Signing certificates carry the team in the trailing parens of the common name:
#   Developer ID Application: Some Name (ABCDE12345)
#   Apple Development: someone@example.com (ABCDE12345)
teams_from_keychain() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(.*\)".*/\1/p' \
        | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p'
}

# A Developer ID certificate is the team you actually ship with, so when the
# machine has several teams that one wins rather than forcing a manual pick.
teams_from_developer_id() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep -F "Developer ID Application" \
        | sed -n 's/.*"\(.*\)".*/\1/p' \
        | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p'
}

# Free Apple IDs get no Developer ID cert, but Xcode still writes provisioning
# profiles containing the team ID.
teams_from_profiles() {
    local dir="$HOME/Library/MobileDevice/Provisioning Profiles"
    [[ -d "$dir" ]] || return 0
    local p
    while IFS= read -r -d '' p; do
        security cms -D -i "$p" 2>/dev/null \
            | plutil -extract TeamIdentifier.0 raw - -o - 2>/dev/null || true
    done < <(find "$dir" -maxdepth 1 -name '*.mobileprovision' -o -name '*.provisionprofile' -print0 2>/dev/null)
}

step "Detecting Apple Developer team"

if [[ -n "$TEAM_ID" ]]; then
    valid_team "$TEAM_ID" \
        || die "'--team ${TEAM_ID}' is not a valid team ID (expected 10 characters, A-Z0-9)."
    info "using team from --team: ${TEAM_ID}"
else
    candidates="$( { teams_from_keychain; teams_from_profiles; } | sort -u | grep . || true)"
    count="$(printf '%s' "$candidates" | grep -c . || true)"

    # Narrow an ambiguous set with the Developer ID team when there is exactly one.
    if (( count > 1 )); then
        preferred="$(teams_from_developer_id | sort -u | grep . || true)"
        if (( $(printf '%s' "$preferred" | grep -c . || true) == 1 )); then
            info "several teams found; preferring the Developer ID team"
            candidates="$preferred"
            count=1
        fi
    fi

    if (( count == 0 )); then
        die "no Apple Developer team found on this machine.

    Sign in to Xcode (Settings > Accounts) with your Apple ID, then re-run.
    Or pass one explicitly:

      ./Scripts/setup-dev.sh --team ABCDE12345

    Find your team ID at https://developer.apple.com/account -> Membership."
    elif (( count > 1 )); then
        printf '\n'
        warn "several teams found on this machine:"
        printf '%s\n' "$candidates" | sed 's/^/      /' >&2
        die "pick one explicitly:  ./Scripts/setup-dev.sh --team <TEAMID>"
    fi

    TEAM_ID="$candidates"
    info "detected team: ${TEAM_ID}"
fi

if (( PRINT_ONLY )); then
    step "Done (--print: nothing written)"
    info "team id: ${TEAM_ID}"
    exit 0
fi

step "Writing Config/Local.xcconfig"

if [[ -f "$LOCAL_CONFIG" ]] && (( ! FORCE )); then
    existing="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM_DEFAULT[[:space:]]*=[[:space:]]*\([A-Z0-9]*\).*/\1/p' "$LOCAL_CONFIG" | head -1)"
    if [[ "$existing" == "$TEAM_ID" ]]; then
        info "already set to ${TEAM_ID} -- nothing to do"
        exit 0
    fi
    die "${LOCAL_CONFIG#"$REPO_ROOT"/} already exists and sets '${existing:-<unset>}'.
    Re-run with --force to overwrite it."
fi

mkdir -p "$(dirname "$LOCAL_CONFIG")"
cat > "$LOCAL_CONFIG" <<EOF
// Generated by Scripts/setup-dev.sh -- untracked, safe to edit or delete.
// Your Apple Developer Team ID, used for local signing.
DEVELOPMENT_TEAM_DEFAULT = ${TEAM_ID}
EOF

info "wrote ${LOCAL_CONFIG#"$REPO_ROOT"/}"

step "Ready"
info "Build with:  xcodebuild -scheme AutoMount -configuration Debug"
info "Or just open AutoMount.xcodeproj in Xcode."
