# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AutoMount is a macOS desktop app (SwiftUI, Swift 5.0, macOS 14.6+) that manages network share mounts. It consists of a main app and a background login-item service that auto-remounts shares.

## Build & Test Commands

```bash
# Build
xcodebuild -scheme AutoMount -configuration Debug
xcodebuild -scheme AutoMountBackground -configuration Debug

# Run all tests (test targets build under the app schemes; there is no
# AutoMountTests or AutoMountBackgroundTests *scheme*)
xcodebuild test -scheme AutoMount -destination 'platform=macOS' -only-testing:AutoMountTests
xcodebuild test -scheme AutoMountBackground -destination 'platform=macOS' -only-testing:AutoMountBackgroundTests

# Run a single test class
xcodebuild test -scheme AutoMount -destination 'platform=macOS' -only-testing:AutoMountTests/ShareDataModelTests

# Run a single test method
xcodebuild test -scheme AutoMount -destination 'platform=macOS' -only-testing:AutoMountTests/ShareDataModelTests/testInitWithStorageLoadsShares

# libMounter package tests (run from the package directory)
cd ../Mounter && swift test
```

Available schemes: `AutoMount`, `AutoMountBackground`

Some `libMounter` tests need the Docker SMB test server; `Scripts/dockerMount.sh`
starts it and is safe to re-run. Without Docker those tests skip or fail to mount.

## Architecture

**Targets:**
- **AutoMount** — Main SwiftUI app with share list UI, add/edit dialogs, menu commands
- **AutoMountBackground** — Login-item background service with menu bar popup, network detection (`Detector`), and automatic remounting (`Remounter`)
- **Common** — Shared code: `ShareDataModel` (main observable model), `Storage` protocol, logging, constants
- **libMounter** — Local Swift package (at `../Mounter`) providing the `Share` struct, `Storage` protocol, and `StorageManager` for actual mount operations

Both apps share data via application group `group.org.tassinari.automount` (UserDefaults suite).

**Key types:**
- `ShareDataModel` (@Observable, @MainActor) — Central app state; loads shares from storage, handles mount/unmount, listens to NSWorkspace volume notifications
- `Detector` — Monitors network changes (NWPathMonitor) and volume mount/unmount events; notifies delegate
- `Remounter` (actor) — Thread-safe auto-remount logic triggered by detector events
- `AddEditModel` — Form validation model for add/edit share dialog

## Concurrency Model

- Modern async/await throughout (no Combine)
- `@MainActor` isolation on all UI-touching code and `ShareDataModel`
- `Remounter` and `AutoMountLog` are actors for thread safety
- `Detector` uses a private DispatchQueue for NWPathMonitor

## Testing Patterns

- XCTest with `@MainActor` and `async throws` test methods
- `MockStorage` implements `Storage` protocol for all tests — never use real system operations in tests
- `MockSMService` mocks `SMAppService` for login-item tests
- Preview content uses `MockStorage` for SwiftUI previews

# Workflow Rules
- **Branching**: Always create a new branch for new tasks or file changes.
- **Naming Convention**: Use the format `feature/task-description` or `fix/task-description`.
- **Process**: Switch to a new branch, perform all work, commit, and push.
