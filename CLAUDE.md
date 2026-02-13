# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MagicMount is a macOS desktop app (SwiftUI, Swift 5.0, macOS 14.6+) that manages network share mounts. It consists of a main app and a background login-item service that auto-remounts shares.

## Build & Test Commands

```bash
# Build
xcodebuild -scheme MagicMount -configuration Debug
xcodebuild -scheme MagicMountBackground -configuration Debug

# Run all tests
xcodebuild test -scheme MagicMountTests
xcodebuild test -scheme MagicMountBackgroundTests

# Run a single test class
xcodebuild test -scheme MagicMountTests -only-testing MagicMountTests/ShareDataModelTests

# Run a single test method
xcodebuild test -scheme MagicMountTests -only-testing MagicMountTests/ShareDataModelTests/testInitWithStorageLoadsShares
```

Available schemes: `MagicMount`, `MagicMountBackground`, `libMounter`

## Architecture

**Targets:**
- **MagicMount** — Main SwiftUI app with share list UI, add/edit dialogs, menu commands
- **MagicMountBackground** — Login-item background service with menu bar popup, network detection (`Detector`), and automatic remounting (`Remounter`)
- **Common** — Shared code: `ShareDataModel` (main observable model), `Storage` protocol, logging, constants
- **libMounter** — Local Swift package (at `../Mounter`) providing the `Share` struct, `Storage` protocol, and `StorageManager` for actual mount operations

Both apps share data via application group `group.org.tassinari.magicmount` (UserDefaults suite).

**Key types:**
- `ShareDataModel` (@Observable, @MainActor) — Central app state; loads shares from storage, handles mount/unmount, listens to NSWorkspace volume notifications
- `Detector` — Monitors network changes (NWPathMonitor) and volume mount/unmount events; notifies delegate
- `Remounter` (actor) — Thread-safe auto-remount logic triggered by detector events
- `AddEditModel` — Form validation model for add/edit share dialog

## Concurrency Model

- Modern async/await throughout (no Combine)
- `@MainActor` isolation on all UI-touching code and `ShareDataModel`
- `Remounter` and `MagicMountLog` are actors for thread safety
- `Detector` uses a private DispatchQueue for NWPathMonitor

## Testing Patterns

- XCTest with `@MainActor` and `async throws` test methods
- `MockStorage` implements `Storage` protocol for all tests — never use real system operations in tests
- `MockSMService` mocks `SMAppService` for login-item tests
- Preview content uses `MockStorage` for SwiftUI previews
