//
//  Storage.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/28/25.
//

import Foundation
import AppKit

public enum ConnectionState: Codable{
    case mounted, unmounted, mounting, unmounting
}

public enum StorageManagerError : Error {
    case doesNotExsist, noUserDefaults
}

public class StorageManager{
    static let storeKey : String = "ShareStoreKey"
    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.org.tassinari.magicmount")) {
        self.userDefaults = defaults
    }
    let userDefaults: UserDefaults?
    
    public func addMount(_ mount: Share) throws {
        mount.managed = true
        guard let defaults = userDefaults else {
            throw StorageManagerError.noUserDefaults
        }
        let encoder = JSONEncoder()
        if let mounts {
            var updated = mounts
            updated.append(mount)
            let data = try encoder.encode(updated)
            defaults.set(data, forKey: StorageManager.storeKey)
            
        }else{
            let data = try encoder.encode([mount])
            defaults.set(data, forKey: StorageManager.storeKey)
        }
    }
    public func deleteMount(_ mount: Share) throws {
        mount.managed = false
        guard let defaults = userDefaults else {
            throw StorageManagerError.noUserDefaults
        }
        guard let mounts else {
            throw StorageManagerError.doesNotExsist
        }
        var modified = mounts
        modified.removeAll(where: {$0 == mount})
        let encoder = JSONEncoder()
        let data = try encoder.encode(modified)
        defaults.set(data, forKey: StorageManager.storeKey)
        
    }
    /// The list of shares in User defaults.  These are added/managed by user.  Connected status is not guarenteed. Use fullMountList for true status
    public var mounts: [Share]? {
        guard let defaults = userDefaults, let data = defaults.data(forKey: StorageManager.storeKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        do{
            let shares = try decoder.decode([Share].self, from: data)
            
            //FIXME: updated connected here
            
            return shares
        }catch{
            //FIXME: logger
            return []
        }
       
    }
    /// The list of all external mounted volumes and volumes managed by user that may not be mounted
    public var fullMountList: [Share]? {
        let connected = Set(MountInfo.mountedVolumes().filter({$0.type != "file"}))
        let managed = Set(self.mounts ?? [])
        for m in managed{
            m.managed = true
            m.connected = connected.contains(m) ? .mounted : .unmounted
        }
        for con in connected{
            con.connected = .mounted
            con.managed = managed.contains(con)
        }
        let merged = connected.union(managed)
        return Array(merged).sorted(by: {$0.name < $1.name})
    }
    
}
