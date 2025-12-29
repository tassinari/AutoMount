//
//  Storage.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/28/25.
//

import Foundation

struct Share : Codable, Sendable, Hashable, Identifiable{
    var id: String{
        return url.absoluteString
    }
    let user : String
    let password : String
    let url : URL
    let name: String
    let mountPoint: String
    let managed: Bool
    var  type: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme ?? ""
    }
    
}
enum StorageManagerError : Error {
    case doesNotExsist, noUserDefaults
}

class StorageManager{
    static let storeKey : String = "ShareStoreKey"
    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.org.tassinari.magicmount")) {
        self.userDefaults = defaults
    }
    let userDefaults: UserDefaults?
    
    func addMount(_ mount: Share) throws {
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
    func deleteMount(_ mount: Share) throws {
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
    var mounts: [Share]? {
        guard let defaults = userDefaults, let data = defaults.data(forKey: StorageManager.storeKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode([Share].self, from: data)
    }
    
}
