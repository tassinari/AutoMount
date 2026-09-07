# AutoMount

A macOS app that keeps your SMB, AFP, and NFS shares mounted — remounting them
automatically on network change, wake, and login. Requires macOS 14.6+.

## Building

Needs Xcode and an Apple ID in **Xcode > Settings > Accounts**. Both targets
carry an app-group entitlement, so a signing team is required; the repo does not
hardcode one. Set yours once:

```bash
git clone https://github.com/tassinari/AutoMount.git
cd AutoMount
./Scripts/setup-dev.sh
```

That detects your team and writes the gitignored `Config/Local.xcconfig`. Then
open `AutoMount.xcodeproj`, or:

```bash
xcodebuild -scheme AutoMount -configuration Debug
xcodebuild -scheme AutoMountBackground -configuration Debug
```

Without a team the build fails with *"has entitlements that require signing with
a development certificate."* Run `setup-dev.sh` first.

Useful flags — `--team ABCDE12345` (if you belong to several), `--print` (detect
only), `--force` (overwrite):

```bash
./Scripts/setup-dev.sh --team ABCDE12345
```

For CI, skip the file and pass the team directly:

```bash
AUTOMOUNT_DEVELOPMENT_TEAM=ABCDE12345 xcodebuild -scheme AutoMount build
```

> Set the team via `Config/Local.xcconfig`, not Xcode's Signing & Capabilities
> editor — the editor writes the ID back into `project.pbxproj`.

`libMounter` is vendored at `Packages/libMounter`; Xcode resolves it as a local
package, so there is nothing extra to clone.

## Tests

Test targets build under the app schemes; there is no separate test scheme.

```bash
xcodebuild test -scheme AutoMount -destination 'platform=macOS' -only-testing:AutoMountTests
xcodebuild test -scheme AutoMountBackground -destination 'platform=macOS' -only-testing:AutoMountBackgroundTests
cd Packages/libMounter && swift test
```

Some `libMounter` tests need a local SMB server:
`Packages/libMounter/Scripts/dockerMount.sh` starts it and is safe to re-run.
The `AutoMountBackground` scheme also starts it from a test pre-action (not a
build one, so plain builds never touch Docker). If Docker isn't running the
pre-action fails silently — tests then fail on their mount calls with no
obvious cause.

## Releases

```bash
./Scripts/build-release.sh --version 1.2.0
./Scripts/build-release.sh --skip-notarize        # fast local check, not distributable
```

Signing identity and team are read from your Developer ID certificate; override
with `AUTOMOUNT_TEAM_ID` / `AUTOMOUNT_SIGN_IDENTITY` or an untracked
`Scripts/signing.env`. Notarization needs credentials stored once:

```bash
xcrun notarytool store-credentials "AutoMountNotary" \
    --apple-id "<your-apple-id>" --team-id "<your-team-id>" \
    --password "<app-specific-password>"
```

## CI releases

Pushing a `v*` tag builds, signs, notarizes and attaches a DMG to a **draft**
GitHub release (`.github/workflows/release.yml`). Run the workflow manually
first — Actions > Release > Run workflow — to check credentials without tagging.

`Scripts/ci-keychain.sh` builds a throwaway keychain from repository secrets so
`build-release.sh` runs unmodified on a runner, and deletes it afterwards.
Required secrets:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i Certificates.p12` — Developer ID cert **and** private key |
| `P12_PASSWORD` | password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string; secures the temporary keychain |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | your 10-character team ID |
| `APPLE_APP_PASSWORD` | app-specific password from appleid.apple.com |

Instead of the last three you can set `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_KEY_BASE64` for App Store Connect API authentication, which does not break
when your Apple ID password changes.

Optionally set the `XCODE_VERSION` repository *variable* (e.g. `26.6`) to pin the
toolchain; without it the workflow uses the newest Xcode on the runner.

## Architecture

| Target | Role |
| --- | --- |
| `AutoMount` | SwiftUI app — share list, add/edit dialogs, settings |
| `AutoMountBackground` | Login item — menu bar popup, network detection, remounting |
| `Common` | Shared model, storage protocol, logging, constants |
| `libMounter` | Vendored package — `Share`, `Storage`, mount operations |

Both apps share state through the `group.org.tassinari.automount` app group.
Concurrency is async/await throughout — no Combine.
