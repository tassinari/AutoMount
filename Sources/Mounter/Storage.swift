//
//  Storage.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/28/25.
//

import Foundation
import AppKit

/// Represents the connection state of a share.
///
/// - mounted: The share is currently mounted and accessible.
/// - unmounted: The share is currently not mounted.
/// - mounting: The share is in the process of being mounted.
/// - unmounting: The share is in the process of being unmounted.
public enum ConnectionState: Codable, Sendable{
    case mounted, unmounted, mounting, unmounting
}

/// Errors that can be thrown by `StorageManager`.
///
/// - doesNotExsist: Thrown when attempting to delete a mount that does not exist in storage.
/// - noUserDefaults: Thrown when the underlying `UserDefaults` instance is not available.
public enum StorageManagerError : Error {
    case doesNotExsist, noUserDefaults
}

/// Manages persistence of user-managed shares and merges them with currently mounted volumes.
///
/// This manager persists shares added or removed by the user in a designated `UserDefaults` suite.
/// It provides a combined view of all mounted volumes and user-managed shares via `fullMountList`.
/// This class is not inherently thread-safe; external synchronization is required if accessed concurrently.
/// The storage suite key used is `"group.org.tassinari.magicmount"`.
public actor StorageManager{
    /// The key used in UserDefaults to persist the encoded shares.
    public static let storeKey : String = "ShareStoreKey"
    
    /// Initializes the storage manager with a specific `UserDefaults` instance.
    ///
    /// - Parameter defaults: The `UserDefaults` instance to use for persistence.
    ///   Defaults to the suite named `"group.org.tassinari.magicmount"`.
    ///   Passing `nil` disables persistence and causes methods to throw `.noUserDefaults`.
    public init(defaults: UserDefaults? = UserDefaults(suiteName: "group.org.tassinari.magicmount")) {
        self.userDefaults = defaults
    }
    let userDefaults: UserDefaults?
    
    /// Adds a share to the list of managed mounts and persists the updated list.
    ///
    /// Marks the share as managed, appends it to the current list if present, or creates a new list.
    /// Persists the updated list encoded as JSON in `UserDefaults`.
    ///
    /// - Parameter mount: The `Share` instance to add.
    /// - Throws: `StorageManagerError.noUserDefaults` if the `UserDefaults` instance is unavailable.
    ///           Encoding errors if JSON encoding fails.
    public func addMount(_ mount: Share) async throws {
        await mount.setManaged(false)
        guard let defaults = userDefaults else {
            throw StorageManagerError.noUserDefaults
        }
        let encoder = JSONEncoder()
        if let mounts = mounts(){
            var updated = mounts
            updated.append(mount)
            let data = try encoder.encode(updated)
            defaults.set(data, forKey: StorageManager.storeKey)
            
        }else{
            let data = try encoder.encode([mount])
            defaults.set(data, forKey: StorageManager.storeKey)
        }
    }
    
    /// Deletes a share from the list of managed mounts and persists the updated list.
    ///
    /// Marks the share as unmanaged, removes all shares equal to the given one from storage,
    /// and persists the updated list encoded as JSON in `UserDefaults`.
    ///
    /// - Parameter mount: The `Share` instance to delete.
    /// - Throws: `StorageManagerError.noUserDefaults` if the `UserDefaults` instance is unavailable.
    ///           `StorageManagerError.doesNotExsist` if no stored mounts exist to delete from.
    ///
    /// - Note: All shares that are equal to `mount` will be removed.
    public func deleteMount(_ mount: Share) async throws {
        await mount.setManaged(false)
        guard let defaults = userDefaults else {
            throw StorageManagerError.noUserDefaults
        }
        guard let mounts = mounts() else {
            throw StorageManagerError.doesNotExsist
        }
        var modified = mounts
        modified.removeAll(where: {$0 == mount})
        let encoder = JSONEncoder()
        let data = try encoder.encode(modified)
        defaults.set(data, forKey: StorageManager.storeKey)
        
    }
    
    /// Reads and decodes the list of shares stored in UserDefaults.
    ///
    /// Returns the array of stored shares decoded from JSON,
    /// or `nil` if no data is present.
    /// Returns an empty array if decoding fails.
    internal func mounts() -> [Share]? {
        guard let defaults = userDefaults, let data = defaults.data(forKey: StorageManager.storeKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        do{
            let shares = try decoder.decode([Share].self, from: data)
           
            return shares
        }catch{
            libMounter.error("Error decoding Share: \(String(describing: error))")
            return nil
        }
       
    }
    
    /// Merges currently mounted volumes with user-managed shares to produce a comprehensive list.
    ///
    /// This property retrieves the list of currently mounted volumes via `MountInfo.mountedVolumes()`,
    /// and the user-managed shares from storage. It marks user-managed shares as managed,
    /// and if any mounted volume matches a managed share (using `Share.equal(to:)`), it marks the share as connected,
    /// and removes the mounted volume from the non-managed list.
    ///
    /// Remaining mounted volumes that are not managed by the user are converted to `Share` instances
    /// using their `.share` property and appended to the result.
    ///
    /// The final list is sorted by `Share.name`.
    ///
    /// - Returns: A sorted array of `Share` instances representing all managed and currently mounted shares,
    ///            or `nil` if there are no managed shares and no mounted volumes.
    ///
    /// - Note: This method assumes `Share.equal(to:)` and `Equatable` semantics are consistent to identify shares correctly.
    public func fullMountList() async -> [Share]{
       
            let connected = MountInfo.mountedVolumes()
            var managed = mounts() ?? []
            var notMananged = connected
            for m in managed{
                await m.setManaged(true)
                var isConnected = false
                for mnt in connected{
                    if mnt.equal(to: m){
                        isConnected = true
                        notMananged.removeAll(where: {$0 == mnt})
                    }
                }
                await m.setConnected(isConnected ? .mounted : .unmounted)
            }
            //Add notManaged as Shares
            let nonMananedShares: [Share] = notMananged.compactMap({$0.share})
            managed.append(contentsOf: nonMananedShares)
            return managed.sorted(by: {$0.name < $1.name})
        
    }
    
}

public extension StorageManager {
    func mount(_ share : Share) async throws -> MountResponse {
        if await share.getConnected() != .unmounted{
            return .alreadyMounted
        }
        if let md = share.mountData{
            do{
                await share.setConnected(.mounting)
                let data =  try await md.mount()
                await share.setConnected(.unmounted)
                return data
            }catch{
                await share.setConnected(.unmounted)
                throw error
            }
        }
        throw MountError.noMountData
    }
    func unmount(_ share: Share) async throws{
        if await share.getConnected() == .unmounting{
            return
        }
        let url = URL(filePath: share.mountPoint)
        await share.setConnected(.unmounting)
        do{
            try await MountData.unmount(url: url)
            await share.setConnected(.unmounted)
        }catch{
            await share.setConnected(.mounted)
            throw error
        }
    }
}

