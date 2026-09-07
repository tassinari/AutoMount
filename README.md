# AutoMount

A macOS app that keeps your network shares mounted.

AutoMount remembers the SMB, AFP, and NFS shares you care about and remounts
them automatically when you reconnect to the network, wake from sleep, or log
in — so a share you marked as managed is simply there, without a trip through
the Finder's Connect to Server dialog.

- **Managed shares** are remounted for you; unmanaged ones stay manual.
- **Network aware** — a background login item watches for network and volume
  changes and remounts when a share becomes reachable again.
- **Keychain based** — credentials live in the macOS keychain. AutoMount never
  stores passwords itself.

Requires macOS 14.6 or later.

## Building

You need Xcode and an Apple ID signed in under **Xcode > Settings > Accounts**.
The app uses an app group shared between the main app and its login item, and
that entitlement requires a real signing team — so the project needs to know
which team to use before it will build.

This repo deliberately does not hardcode a Team ID. Set yours once:

```bash
git clone https://github.com/tassinari/AutoMount.git
cd AutoMount
./Scripts/setup-dev.sh
```

`setup-dev.sh` finds your team in the keychain (or your provisioning profiles)
and writes it to `Config/Local.xcconfig`, which is gitignored. If you belong to
several teams, pass the one you want:

```bash
./Scripts/setup-dev.sh --team ABCDE12345          # find it at developer.apple.com > Membership
./Scripts/setup-dev.sh --print                    # show what it detects, write nothing
./Scripts/setup-dev.sh --force                    # overwrite an existing value
```

Then open `AutoMount.xcodeproj`, or build from the command line:

```bash
xcodebuild -scheme AutoMount -configuration Debug
xcodebuild -scheme AutoMountBackground -configuration Debug
```

Instead of the config file you can export `AUTOMOUNT_DEVELOPMENT_TEAM`, or pass
`-xcconfig` to `xcodebuild` — useful in CI, where writing a file is awkward:

```bash
AUTOMOUNT_DEVELOPMENT_TEAM=ABCDE12345 xcodebuild -scheme AutoMount build
```

> Set your team in `Config/Local.xcconfig` rather than through Xcode's
> Signing & Capabilities editor. The editor writes the ID straight into
> `project.pbxproj`, which puts it back in version control.

### libMounter

The project depends on `libMounter`, a local Swift package expected at
`../Mounter` — clone it beside this repo, or the build cannot resolve it.

## Tests

Test targets build under the app schemes; there is no separate test scheme.

```bash
xcodebuild test -scheme AutoMount -destination 'platform=macOS' -only-testing:AutoMountTests
xcodebuild test -scheme AutoMountBackground -destination 'platform=macOS' -only-testing:AutoMountBackgroundTests
```

Some `libMounter` tests need a local SMB server in Docker. The helper lives in
the package, not this repo — run `../Mounter/Scripts/dockerMount.sh`, which is
safe to re-run. Without Docker those tests skip or fail to mount.

## Releases

`Scripts/build-release.sh` produces a notarized, stapled DMG. It reads your
signing identity and team from the Developer ID certificate in your keychain,
so there is nothing to configure for a normal release build:

```bash
./Scripts/build-release.sh --version 1.2.0
./Scripts/build-release.sh --skip-notarize        # fast local check, not distributable
```

Notarization needs credentials stored once:

```bash
xcrun notarytool store-credentials "AutoMountNotary" \
    --apple-id "<your-apple-id>" --team-id "<your-team-id>" \
    --password "<app-specific-password>"
```

Generate the app-specific password at [appleid.apple.com](https://appleid.apple.com)
under Sign-In and Security. Override the detected signing values with
`AUTOMOUNT_TEAM_ID` / `AUTOMOUNT_SIGN_IDENTITY`, or put them in an untracked
`Scripts/signing.env`.

## Architecture

| Target | Role |
| --- | --- |
| `AutoMount` | SwiftUI app — share list, add/edit dialogs, settings |
| `AutoMountBackground` | Login item — menu bar popup, network detection, remounting |
| `Common` | Shared model, storage protocol, logging, constants |
| `libMounter` | Local package (`../Mounter`) — `Share`, `Storage`, mount operations |

Both apps share state through the `group.org.tassinari.automount` app group.
`ShareDataModel` is the central `@Observable @MainActor` model; `Detector`
watches the network with `NWPathMonitor`; `Remounter` is an actor holding the
auto-remount logic. Concurrency is async/await throughout — no Combine.
