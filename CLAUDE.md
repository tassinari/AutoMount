# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mounter is a Swift package (`libMounter`) for managing network share (SMB, AFP, NFS) mounting on macOS. It uses the NetFS framework for low-level mount operations and persists managed shares via UserDefaults (suite: `group.org.tassinari.magicmount`).

## Build & Test Commands

```bash
swift build          # Build the library
swift test           # Run all tests (requires Docker for integration tests)
swift test --filter MounterTests.ShareTests          # Run a single test class
swift test --filter MounterTests.ShareTests/testName # Run a single test method
```

Integration tests spin up a Docker Samba container (dockurr/samba) on localhost:1445 via `Scripts/dockerMount.sh` and tear down via `Scripts/dockerUnmount.sh`.

## Architecture

**Swift 6.2 / macOS 14+ / Swift Package Manager**

Four source files in `Sources/Mounter/`:

- **Share.swift** — `Share` model (Codable, Sendable, Hashable) representing a network share with a `ConnectionState` enum (mounted/unmounted/mounting/unmounting). State transitions use immutable copy methods (`mountedCopy`, `unmountedCopy`, etc.) rather than mutation.

- **Mount.swift** — `MountData` (internal) handles NetFS mount/unmount calls. `MountInfo` queries the system for currently mounted volumes. `MountResponse` enum captures all possible mount outcomes (success, auth error, timeout, etc.).

- **Storage.swift** — `StorageManager` is a Swift **actor** providing thread-safe persistence to UserDefaults with JSON encoding. `fullMountList()` merges user-managed shares with system-detected mounted volumes.

- **Logger.swift** — Thin wrapper around `os.Logger` (subsystem from bundle identifier, category "Mounter").

### Key Design Patterns

- **Actor concurrency**: `StorageManager` is an actor; all public methods are async. Share types are Sendable.
- **Immutable state transitions**: Share state changes produce new Share instances rather than mutating in place.
- **Managed vs unmanaged shares**: Managed shares are user-saved and persisted; unmanaged shares are system-detected mounts not tracked by the user.

### Public API Surface

`StorageManager` is the main entry point: `addMount`, `deleteMount`, `mount`, `unmount`, `fullMountList`. `Share`, `ConnectionState`, `MountResponse`, `MountError`, and `StorageManagerError` are the public types.

## Testing

Tests are in `Tests/MounterTests/` with a `BaseTest` class that manages Docker container lifecycle. Test UserDefaults suite: `group.org.tassinari.magicmount.test`. Tests cover URL construction, mount/unmount operations, state transitions, JSON serialization, and storage aggregation.
