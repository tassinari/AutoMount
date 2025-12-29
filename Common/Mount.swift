
import Foundation
import NetFS


enum MountScheme : String{
    case smb = "smb"
}
enum MountError: Error{
    case badURL
}
/// Errors:
///  os errors are defined in <sys/errno.h>
enum MountResponse{
    case genericError(Error)
    case success([String])
    case authenticationError
    case cannotFindHost
    case timeout
    case noSuchFileOrDirectory
    case connectionRefused
    case alreadyMounted
   
}

struct MountInfo{
    static func mountedVolumes() -> [Share] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeIsLocalKey,
                .volumeNameKey,
                .volumeURLForRemountingKey,
                .volumeUUIDStringKey
            ],
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var result: [Share] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [
                .volumeIsLocalKey,
                .volumeNameKey,
                .volumeUUIDStringKey,
                .volumeURLForRemountingKey,
                .pathKey
            ])
            let name = values?.volumeName ?? url.lastPathComponent
            let isLocal = values?.volumeIsLocal ?? false
            let uuid = values?.volumeUUIDString ?? UUID().uuidString
            let mount = values?.path ?? "/"
            let remote = values?.volumeURLForRemounting ?? url
            result.append(Share(user: "", password: "", url: remote, name: name, mountPoint: mount, managed: false))
        }
        return result
    }
    
    static func isVolumeMounted(at remoteURL: URL) -> Bool {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) else {
            return false
        }
        for url in urls {
            if url == remoteURL { return true }
        }
        return false
    }
}

struct MountData{
    let scheme: MountScheme
    let host: String
    let port : Int?
    let user: String?
    let password: String?
    let shareName: String
    
    var url: URL{
        get throws{
            var components = URLComponents()
            components.scheme = scheme.rawValue
            components.host = host
            components.path = "/\(shareName)"
            if let user{
                components.user = user
            }
            if let password{
                components.password = password
            }
            if let port{
                components.port = port
            }else{
                components.port = 445
            }
            guard let url = components.url else{
                throw MountError.badURL
            }
            return url
        }
    }
    func mount() throws -> MountResponse {
        
        
        let url = try self.url
        var cfArray: Unmanaged<CFArray>?
        let mountD = NSMutableDictionary()
        let optD = NSMutableDictionary()
        mountD.setValue(kNAUIOptionNoUI, forKey:kNAUIOptionKey)
        let response = NetFSMountURLSync(url as CFURL, nil, nil, nil, mountD as CFMutableDictionary, optD as CFMutableDictionary, &cfArray)
        print("Responses: \(response)")
        switch response{
        case 0:
            let messages: [String] = {
                guard let unmanaged = cfArray else { return [] }
                let arrayRef: CFArray = unmanaged.takeRetainedValue()
                let anyArray = arrayRef as [AnyObject]
                return anyArray.compactMap { $0 as? String }
            }()
            return .success(messages)
        case EAUTH:
            return .authenticationError
        case EHOSTUNREACH:
            return .cannotFindHost
        case ETIMEDOUT:
            return .timeout
        case ECONNREFUSED, ELOOP:
            return .connectionRefused
        case ENOENT:
            return .noSuchFileOrDirectory
        case EEXIST:
            return .alreadyMounted
            
        default:
            return .genericError(NSError(domain: "NetFS", code: Int(response), userInfo: nil))
        }
    }
    
}

