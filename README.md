# AutoMount

A macOS app that keeps your SMB, AFP, and NFS shares mounted — remounting them
automatically on network change, wake, and login. Requires macOS 14.6+.

### [Download AutoMount][latest]

[latest]: https://github.com/tassinari/AutoMount/releases/latest/download/AutoMount.dmg

Open the disk image and drag AutoMount to Applications. The app is signed and
notarized, so it opens without a Gatekeeper warning. Every build is also listed
on the [releases page](https://github.com/tassinari/AutoMount/releases).

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

Pushing a `v*` tag builds, signs, notarizes and **publishes** a GitHub release
with the DMG attached (`.github/workflows/release.yml`). It goes live as soon as
the run finishes, so tag deliberately. Run the workflow manually first — Actions
> Release > Run workflow — to check a build without tagging or publishing.

A tag containing a hyphen (`v1.1.0-beta.1`, `v1.0.0-rc.2`) is marked a
prerelease: it publishes, but does not become `releases/latest`, so the download
link keeps pointing at the newest stable build.

`Scripts/ci-keychain.sh` builds a throwaway keychain from repository secrets so
`build-release.sh` runs unmodified on a runner, and deletes it afterwards.
Required secrets:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i Certificates.p12` — Developer ID cert **and** private key |
| `P12_PASSWORD` | password used when exporting the `.p12` |
| `DEV_CERTIFICATE_BASE64` | an **Apple Development** cert, same treatment — the archive step signs with it before export re-signs with Developer ID |
| `DEV_P12_PASSWORD` | its password (omit if the same as `P12_PASSWORD`) |
| `KEYCHAIN_PASSWORD` | any random string; secures the temporary keychain |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | your 10-character team ID |
| `APPLE_APP_PASSWORD` | app-specific password from appleid.apple.com |

**Provisioning profiles must be supplied.** A personal Apple team is not allowed
to create "Developer ID" provisioning profiles through the API — Apple rejects it
with *"Team ... does not have permission to create Developer ID provisioning
profiles"* — so a runner cannot mint its own. Export the ones Xcode already made
on your machine and store them as a secret:

```bash
./Scripts/export-profiles.sh --upload      # or omit --upload and set it by hand
```

That sets `PROVISIONING_PROFILES_BASE64`. With it in place the build reuses those
profiles offline and never asks Apple for new ones. Re-run it if the profiles
expire.

**An App Store Connect API key is optional**, not optional: creating provisioning
profiles needs an authenticated Apple account, and a certificate is not one. A
runner has no Xcode account, so `-allowProvisioningUpdates` fails with *"No
Accounts: Add a new account in Accounts settings"* without it.

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | the key's ID, e.g. `2X9R4HXF34` |
| `ASC_ISSUER_ID` | issuer UUID, shown above the keys list |
| `ASC_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` |

Create one at [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api)
> Integrations > App Store Connect API, with the **Developer** role or higher.
The `.p8` downloads **once** — keep it somewhere safe. The key also authenticates
notarization, replacing `APPLE_ID` / `APPLE_APP_PASSWORD`, and does not break when
your Apple ID password changes.

Optionally set the `XCODE_VERSION` repository *variable* (e.g. `26.6`) to pin the
toolchain; without it the workflow uses the newest Xcode on the runner.

CI does **not** run the test suites, for two reasons. Some `libMounter` tests
need the Docker SMB container, which is not on the runner. And the test targets
sign with **Apple Development**, a different certificate from the Developer ID
one CI holds — so `xcodebuild test` cannot sign them at all, failing with "No
signing certificate Mac Development found".

Ticking `run_tests` therefore needs an Apple Development certificate added to
the CI keychain as well; the workflow checks for it and fails early with that
message rather than deep inside `xcodebuild`. Leave it unticked for releases —
signing correctness is verified in the release script's own verification phase.

## Architecture

| Target | Role |
| --- | --- |
| `AutoMount` | SwiftUI app — share list, add/edit dialogs, settings |
| `AutoMountBackground` | Login item — menu bar popup, network detection, remounting |
| `Common` | Shared model, storage protocol, logging, constants |
| `libMounter` | Vendored package — `Share`, `Storage`, mount operations |

Both apps share state through the `group.org.tassinari.automount` app group.
Concurrency is async/await throughout — no Combine.
