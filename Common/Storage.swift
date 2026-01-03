//
//  Storage.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/28/25.
//

import Foundation

@Observable class Share: Codable{
    init(user: String, password: String, url: URL, name: String, mountPoint: String, managed: Bool, connected: Bool) {
        self.user = user
        self.password = password
        self.url = url
        self.name = name
        self.mountPoint = mountPoint
        self.managed = managed
        self.connected = connected
    }
    required init(from decoder: Decoder) throws {
           let container = try decoder.container(keyedBy: CodingKeys.self)
           user = try container.decode(String.self, forKey: .user)
           password = try container.decode(String.self, forKey: .password)
           url = try container.decode(URL.self, forKey: .url)
           name = try container.decode(String.self, forKey: .name)
           mountPoint = try container.decode(String.self, forKey: .mountPoint)
           managed = try container.decode(Bool.self, forKey: .managed)
           connected = try container.decode(Bool.self, forKey: .connected)
    }
    func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user, forKey: .user)
            try container.encode(password, forKey: .password)
            try container.encode(url, forKey: .url)
            try container.encode(name, forKey: .name)
            try container.encode(mountPoint, forKey: .mountPoint)
            try container.encode(managed, forKey: .managed)
            try container.encode(connected, forKey: .connected)
    }
    
    var user : String
    var password : String
    let url : URL
    let name: String
    let mountPoint: String
    var  type: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme ?? ""
    }
    var managed : Bool
    var connected : Bool
    
    enum CodingKeys: String, CodingKey {
        case user
        case password
        case url
        case name
        case mountPoint
        case managed
        case connected
    }
   
}

extension Share {
    
    var mountData : MountData?{
        if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),let scheme = comp.scheme, let host = comp.host{
            return MountData(scheme: scheme , host: host, port: comp.port, user: comp.user, password: comp.password, shareName: name)
        }
        return nil
    }
   
    func unmount() async throws{
        let url = URL(filePath: mountPoint)
        try await MountData.unmount(url: url)
    }
    func mount() async throws -> MountResponse{
        if let mountData{
            return try await mountData.mount()
        }
        throw MountError.noMountData
    }
}
extension Share: Hashable, Identifiable{
    var id: String{
        return url.absoluteString
    }
    static func == (lhs: Share, rhs: Share) -> Bool {
        guard let lcomp = URLComponents(url: lhs.url, resolvingAgainstBaseURL: false),
              let rcomp = URLComponents(url: rhs.url, resolvingAgainstBaseURL: false) else {return false}
        return lcomp.scheme == rcomp.scheme && lcomp.host == rcomp.host && lcomp.path == rcomp.path
        
    }
    func hash(into hasher: inout Hasher) {
        guard let uRLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else{
            hasher.combine(id)
            return
        }
        hasher.combine(uRLComponents.scheme)
        hasher.combine(uRLComponents.host)
        hasher.combine(uRLComponents.path)
        
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
    func deleteMount(_ mount: Share) throws {
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
    var mounts: [Share]? {
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
    
}
