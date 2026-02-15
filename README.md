# libMounter

A Swift package for managing network share (SMB, AFP, NFS) mounting on macOS. It uses the NetFS framework for low-level mount operations and persists user-managed shares via UserDefaults.

## Requirements

- macOS 14+
- Swift 6.2
- Xcode 16+

## Installation

Add libMounter to your project using Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/tassinari/Mounter.git", branch: "main")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "libMounter", package: "Mounter")
    ]
)
```

## Quick Start

```swift
import libMounter

// Create a StorageManager (uses default UserDefaults suite)
let storage = StorageManager()

// Create a share
let share = Share(
    url: URL(string: "smb://fileserver.local/Documents")!,
    name: "Documents",
    mountPoint: nil,
    managed: true,
    connected: .unmounted
)

// Add it to managed storage
try await storage.addMount(share)

// Mount the share
let response = try await storage.mount(share)
switch response {
case .success(let mountPath):
    print("Mounted at: \(mountPath ?? "unknown")")
case .authenticationError:
    print("Invalid credentials")
case .cannotFindHost:
    print("Server not reachable")
case .timeout:
    print("Connection timed out")
case .alreadyMounted:
    print("Already mounted")
case .connectionRefused:
    print("Connection refused")
case .noSuchFileOrDirectory:
    print("Share not found on server")
case .genericError(let error):
    print("Error: \(error)")
}

// Get all shares (managed + system-detected)
let allShares = await storage.fullMountList()

// Unmount
try await storage.unmount(share)
```

## API Reference

### StorageManager

The main entry point. An actor providing thread-safe persistence and mount operations.

| Method | Description |
|--------|-------------|
| `init(defaults:)` | Initialize with a custom `UserDefaults` instance |
| `addMount(_:)` | Persist a share to managed storage |
| `deleteMount(_:)` | Remove a share from managed storage |
| `mount(_:ui:)` | Mount a share via NetFS. Set `ui: true` to allow system auth dialogs |
| `unmount(_:)` | Unmount a currently mounted share |
| `fullMountList()` | Merge managed shares with system-detected mounted volumes |

### Share

An immutable value type representing a network share.

| Property | Type | Description |
|----------|------|-------------|
| `url` | `URL` | Remote share URL (e.g. `smb://server/share`) |
| `name` | `String?` | Display name |
| `mountPoint` | `String?` | Local filesystem mount path |
| `managed` | `Bool` | Whether the share is user-managed |
| `connected` | `ConnectionState` | Current connection state |
| `type` | `String` | URL scheme (`smb`, `afp`, `nfs`) |

State transitions produce new instances:

```swift
let mounting = share.mountingCopy     // .mounting state
let unmounting = share.unmountingCopy // .unmounting state
```

### ConnectionState

```swift
public enum ConnectionState {
    case mounted      // Share is accessible
    case unmounted    // Share is not mounted
    case mounting     // Mount in progress
    case unmounting   // Unmount in progress
}
```

### MountResponse

The result of a mount operation, used with pattern matching:

```swift
switch response {
case .success(let path):    // Mounted successfully
case .authenticationError:  // Bad credentials
case .cannotFindHost:       // Host unreachable
case .timeout:              // Connection timed out
case .connectionRefused:    // Server refused connection
case .noSuchFileOrDirectory:// Remote path not found
case .alreadyMounted:       // Volume already mounted
case .genericError(let e):  // Other OS-level error
}
```

### Error Types

- **`MountError`** — Thrown during mount preparation: `.badURL`, `.noMountData`
- **`StorageManagerError`** — Thrown by storage operations: `.doesNotExsist`, `.noUserDefaults`

## Architecture

- **Actor concurrency**: `StorageManager` is a Swift actor, ensuring thread-safe access to UserDefaults. All public methods are async.
- **Immutable state transitions**: `Share` is a value type. State changes (mounting, unmounting) produce new instances rather than mutating in place.
- **Managed vs unmanaged shares**: Managed shares are user-saved and persisted; unmanaged shares are system-detected mounts discovered via `FileManager.mountedVolumeURLs`.
- **NetFS integration**: Low-level mount/unmount operations use Apple's NetFS framework via `NetFSMountURLSync`.

## Testing

Tests require Docker for integration testing with a Samba container:

```bash
swift test                                          # Run all tests
swift test --filter MounterTests.ShareTests         # Run a single test class
swift test --filter MounterTests.ShareTests/testName # Run a single test method
```

Integration tests automatically spin up a Docker Samba container (`dockurr/samba`) on `localhost:1445`.

## License

TBD
