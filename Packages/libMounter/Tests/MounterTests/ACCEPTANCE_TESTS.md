# libMounter — Acceptance Test Plan (GWT)

## Context
Acceptance test plan for the libMounter Swift package covering all public API surface areas. Tests are written in Given-When-Then format. Integration tests require a Docker Samba container via `Scripts/dockerMount.sh`.

---

## 1. Share Model

### 1.1 Share initializes with all properties
- **Given** a valid SMB URL, name, mount point, managed flag, and connection state
- **When** a `Share` is initialized with those values
- **Then** all properties (`url`, `name`, `mountPoint`, `managed`, `connected`) match the provided values

### 1.2 Share type is derived from URL scheme
- **Given** shares with `smb://`, `afp://`, and `nfs://` URLs
- **When** the `type` property is accessed
- **Then** it returns `"smb"`, `"afp"`, and `"nfs"` respectively

### 1.3 Share identity includes URL, managed flag, and connection state
- **Given** two shares with the same URL but different `managed` or `connected` values
- **When** their `id` properties are compared
- **Then** the IDs are different

### 1.4 Shares with the same URL, managed flag, and state are equal
- **Given** two shares constructed with identical `url`, `managed`, and `connected`
- **When** compared with `==`
- **Then** they are equal and produce the same hash value

### 1.5 Shares with different hosts are not equal
- **Given** two shares with different host components in their URLs
- **When** compared with `==`
- **Then** they are not equal

### 1.6 Set deduplication works for identical shares
- **Given** two equal `Share` instances
- **When** both are inserted into a `Set<Share>`
- **Then** the set contains only one element

### 1.7 sameURL ignores state and managed flag
- **Given** two shares with the same URL but different `managed` and `connected` values
- **When** `sameURL(as:)` is called
- **Then** it returns `true`

### 1.8 sameURL returns false for different URLs
- **Given** two shares with different host or path components
- **When** `sameURL(as:)` is called
- **Then** it returns `false`

### 1.9 Share name and mountPoint can be nil
- **Given** a share initialized with `name: nil` and `mountPoint: nil`
- **When** the share is inspected
- **Then** `name` is `nil` and `mountPoint` is `nil`

---

## 2. Share State Transitions

### 2.1 mountingCopy sets state to mounting
- **Given** a share in `.unmounted` state
- **When** `mountingCopy` is accessed
- **Then** the returned share has `connected == .mounting` and all other properties unchanged

### 2.2 unmountingCopy sets state to unmounting
- **Given** a share in `.mounted` state
- **When** `unmountingCopy` is accessed
- **Then** the returned share has `connected == .unmounting` and all other properties unchanged

### 2.3 mountedCopy sets state to mounted
- **Given** a share in `.mounting` state
- **When** `mountedCopy` is accessed
- **Then** the returned share has `connected == .mounted`

### 2.4 unmountedCopy sets state to unmounted
- **Given** a share in `.unmounting` state
- **When** `unmountedCopy` is accessed
- **Then** the returned share has `connected == .unmounted`

### 2.5 managedCopy sets managed to true
- **Given** an unmanaged share (`managed == false`)
- **When** `managedCopy` is accessed
- **Then** the returned share has `managed == true`

### 2.6 unmanagedCopy sets managed to false
- **Given** a managed share (`managed == true`)
- **When** `unmanagedCopy` is accessed
- **Then** the returned share has `managed == false`

---

## 3. Share Codable Round-Trip

### 3.1 Encode and decode preserves all properties
- **Given** a share with non-nil `name`, `mountPoint`, `managed == true`, and `connected == .mounted`
- **When** the share is JSON-encoded and then decoded
- **Then** the decoded share equals the original

### 3.2 Encode and decode preserves nil name and mountPoint
- **Given** a share with `name: nil` and `mountPoint: nil`
- **When** the share is JSON-encoded and then decoded
- **Then** `name` and `mountPoint` remain `nil` on the decoded share

### 3.3 All ConnectionState cases survive round-trip
- **Given** shares in each `ConnectionState` (`.mounted`, `.unmounted`, `.mounting`, `.unmounting`)
- **When** each is JSON-encoded and decoded
- **Then** the `connected` property matches the original for every case

---

## 4. StorageManager Persistence

### 4.1 addMount saves a share that can be loaded
- **Given** an empty StorageManager
- **When** `addMount` is called with a valid share
- **Then** the share appears in the stored mounts

### 4.2 addMount saves multiple shares
- **Given** an empty StorageManager
- **When** `addMount` is called 10 times with different shares
- **Then** all 10 shares are returned by `mounts()`

### 4.3 addMount marks the share as managed
- **Given** a share with `managed == false`
- **When** `addMount` is called
- **Then** the stored share has `managed == true`

### 4.4 addMount throws noUserDefaults when defaults are nil
- **Given** a StorageManager initialized with `nil` defaults
- **When** `addMount` is called
- **Then** it throws `StorageManagerError.noUserDefaults`

### 4.5 deleteMount removes the share by URL
- **Given** a StorageManager with 10 saved shares
- **When** `deleteMount` is called for one of them
- **Then** 9 shares remain and the deleted share is absent

### 4.6 deleteMount matches by URL regardless of state
- **Given** a share stored with `.unmounted` state
- **When** `deleteMount` is called with the same URL but `.mounted` state
- **Then** the share is deleted successfully

### 4.7 deleteMount throws doesNotExist when share is not found
- **Given** a StorageManager with no stored shares
- **When** `deleteMount` is called
- **Then** it throws `StorageManagerError.doesNotExsist`

### 4.8 deleteMount throws noUserDefaults when defaults are nil
- **Given** a StorageManager initialized with `nil` defaults
- **When** `deleteMount` is called
- **Then** it throws `StorageManagerError.noUserDefaults`

### 4.9 mounts returns nil when defaults are nil
- **Given** a StorageManager initialized with `nil` defaults
- **When** `mounts()` is called
- **Then** it returns `nil`

### 4.10 Corrupt data in UserDefaults returns nil
- **Given** invalid (non-JSON) data stored under the share store key
- **When** `mounts()` is called
- **Then** it returns `nil` and an error is logged

---

## 5. StorageManager Mount Operations

### 5.1 Mount succeeds for a valid SMB share
- **Given** a running Samba server and a valid SMB share URL
- **When** `mount(_:)` is called
- **Then** it returns `.success` with a non-nil mount path, and the volume is accessible on disk

### 5.2 Mount returns alreadyMounted for a mounted share
- **Given** a share with `connected == .mounted`
- **When** `mount(_:)` is called
- **Then** it returns `.alreadyMounted` without invoking NetFS

### 5.3 Mount throws noMountData for an empty URL
- **Given** a share with an empty or unparseable URL
- **When** `mount(_:)` is called
- **Then** it throws `MountError.noMountData`

### 5.4 Mount returns connectionRefused for wrong port
- **Given** a share URL pointing to a port with no SMB service
- **When** `mount(_:)` is called
- **Then** it returns `.connectionRefused`

### 5.5 Mount returns cannotFindHost for unknown host
- **Given** a share URL with a nonexistent hostname
- **When** `mount(_:)` is called
- **Then** it returns `.cannotFindHost`

### 5.6 Mount returns timeout for unreachable port
- **Given** a share URL pointing to a port that silently drops packets
- **When** `mount(_:)` is called
- **Then** it returns `.timeout`

### 5.7 Mount returns noSuchFileOrDirectory for bad share path
- **Given** a share URL with a valid host but nonexistent share name
- **When** `mount(_:)` is called
- **Then** it returns `.noSuchFileOrDirectory`

### 5.8 Double mount returns alreadyMounted
- **Given** a share that has been successfully mounted via NetFS
- **When** `mount(_:)` is called a second time with the same URL
- **Then** it returns `.alreadyMounted`

---

## 6. StorageManager Unmount Operations

### 6.1 Unmount removes a mounted volume
- **Given** a share that was successfully mounted
- **When** `unmount(_:)` is called
- **Then** the volume is no longer present on disk

### 6.2 Unmount is a no-op for unmounting state
- **Given** a share with `connected == .unmounting`
- **When** `unmount(_:)` is called
- **Then** no error is thrown and the volume remains unchanged

### 6.3 Unmount is a no-op for unmounted share
- **Given** a share with `connected == .unmounted`
- **When** `unmount(_:)` is called
- **Then** no error is thrown

### 6.4 Unmount throws for invalid mount point
- **Given** a share with `connected == .mounted` and a `mountPoint` that does not exist on disk
- **When** `unmount(_:)` is called
- **Then** it throws a `CocoaError`

---

## 7. Full Mount List

### 7.1 Unmanaged system mounts appear in fullMountList
- **Given** a volume mounted via NetFS but not added to StorageManager
- **When** `fullMountList()` is called
- **Then** the volume appears with `managed == false`

### 7.2 Managed share reflects mounted state
- **Given** a share added via `addMount` and then mounted on disk
- **When** `fullMountList()` is called
- **Then** the share appears with `managed == true` and `connected == .mounted`

### 7.3 Managed share reflects unmounted state
- **Given** a share added via `addMount` that is not currently mounted on disk
- **When** `fullMountList()` is called
- **Then** the share appears with `managed == true` and `connected == .unmounted`

### 7.4 Full lifecycle: add, mount, unmount, remount
- **Given** a share added via `addMount`
- **When** it is mounted, then unmounted, then remounted
- **Then** `fullMountList()` shows `managed == true` and `connected == .mounted` after remount

### 7.5 List is sorted by name
- **Given** multiple managed and unmanaged shares
- **When** `fullMountList()` is called
- **Then** the returned array is sorted alphabetically by share name

### 7.6 Only netwok volumes are listed
- **Given** Multiple mounted drives are available
- **When** `fullMountList()` is called
- **Then** only non local drives are listed, USB, DMG, local drives are excluded

---

## 8. Error Types

### 8.1 MountError.badURL
- **Given** a malformed URL that cannot be decomposed
- **When** `MountData` initialization is attempted
- **Then** `MountError.badURL` is thrown

### 8.2 MountError.noMountData
- **Given** a share whose URL produces no valid `MountData`
- **When** `StorageManager.mount(_:)` is called
- **Then** `MountError.noMountData` is thrown

### 8.3 StorageManagerError.noUserDefaults
- **Given** a StorageManager initialized with `nil` defaults
- **When** any persistence method is called
- **Then** `StorageManagerError.noUserDefaults` is thrown

### 8.4 StorageManagerError.doesNotExist
- **Given** a StorageManager with no stored shares
- **When** `deleteMount` is called for a non-existent share
- **Then** `StorageManagerError.doesNotExsist` is thrown

### 8.5 MountResponse covers all NetFS error codes
- **Given** the `MountResponse` enum
- **When** all cases are enumerated
- **Then** it includes: `success`, `genericError`, `authenticationError`, `cannotFindHost`, `timeout`, `noSuchFileOrDirectory`, `connectionRefused`, and `alreadyMounted`
