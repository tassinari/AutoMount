import Foundation
import SwiftUI

struct MountStorage : Codable, Sendable, Equatable, Hashable{
    let user : String
    let url : String
    let password : String
    
}

enum NewMountModelError : Swift.Error {
    case missingValues, doesNotExsist
}
@MainActor @Observable final class CreateMountModel {
   
    var urlString: String
    var username: String
    var password: String

    init(urlString: String = "", username: String = "", password: String = "") {
        self.password = password
        self.urlString = urlString
        self.username = username
    }

    func clear() {
        urlString = ""
        username = ""
        password = ""
    }
   
    func saveAll() async throws {
        guard !urlString.isEmpty, !username.isEmpty, !password.isEmpty else {
            throw NewMountModelError.missingValues
        }

        let mount = MountStorage(user: username, url: urlString, password: password)

        try await Task {
            try StorageManager.shared.addMount(mount)
        }.value
    }
}

class StorageManager{
    static let shared = StorageManager()
    private init() {
        self.userDefaults = .standard
    }
    let userDefaults: UserDefaults
    
    func addMount(_ mount: MountStorage) throws {
        let encoder = JSONEncoder()
        if let mounts {
            var updated = mounts
            updated.append(mount)
            let data = try encoder.encode(updated)
            userDefaults.set(data, forKey: MounterConstants.mountsStorageKey)
            
        }else{
            let data = try encoder.encode([mount])
            userDefaults.set(data, forKey: MounterConstants.mountsStorageKey)
        }
    }
    func deleteMount(_ mount: MountStorage) throws {
        guard let mounts else {
            throw NewMountModelError.doesNotExsist
        }
        var modified = mounts
        modified.removeAll(where: {$0 == mount})
        let encoder = JSONEncoder()
        let data = try encoder.encode(modified)
        userDefaults.set(data, forKey: MounterConstants.mountsStorageKey)
        
    }
    var mounts: [MountStorage]? {
        guard let data = userDefaults.data(forKey: MounterConstants.mountsStorageKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode([MountStorage].self, from: data)
    }
    
}
