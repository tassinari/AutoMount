
import Foundation
import NetFS

enum MountError: Error{
    case badURL, noMountData
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
                .volumeNameKey,
                .volumeURLForRemountingKey,
                .pathKey
            ])
            let name = values?.volumeName ?? url.lastPathComponent
            let mount = values?.path ?? "/"
            let remote = values?.volumeURLForRemounting ?? url
            result.append(Share(user: "", password: "", url: remote, name: name, mountPoint: mount, managed: false, connected: true))
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
            let values = try? url.resourceValues(forKeys: [
                .volumeURLForRemountingKey
            ])
            if url == remoteURL { return true }
        }
        return false
    }
}

struct MountData{
    let scheme: String
    let host: String
    let port : Int?
    let user: String?
    let password: String?
    let shareName: String
    
    var url: URL{
        get throws{
            var components = URLComponents()
            components.scheme = scheme
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
    func mount() async throws -> MountResponse {
       
        let url = try self.url
        var cfArray: Unmanaged<CFArray>?
        let mountD = NSMutableDictionary()
        let optD = NSMutableDictionary()
        mountD.setValue(kNAUIOptionNoUI, forKey:kNAUIOptionKey)
        return await withCheckedContinuation { cont in
            let response = NetFSMountURLSync(url as CFURL, nil, nil, nil, mountD as CFMutableDictionary, optD as CFMutableDictionary, &cfArray)
            print("Responses: \(response)")
            var retVal: MountResponse = .alreadyMounted
            switch response{
            case 0:
                let messages: [String] = {
                    guard let unmanaged = cfArray else { return [] }
                    let arrayRef: CFArray = unmanaged.takeRetainedValue()
                    let anyArray = arrayRef as [AnyObject]
                    return anyArray.compactMap { $0 as? String }
                }()
                retVal =  .success(messages)
            case EAUTH:
                retVal =  .authenticationError
            case EHOSTUNREACH:
                retVal =  .cannotFindHost
            case ETIMEDOUT:
                retVal =  .timeout
            case ECONNREFUSED, ELOOP:
                retVal =  .connectionRefused
            case ENOENT:
                retVal =  .noSuchFileOrDirectory
            case EEXIST:
                retVal =  .alreadyMounted
                
            default:
                retVal =  .genericError(NSError(domain: "NetFS", code: Int(response), userInfo: nil))
            }
            cont.resume(returning: retVal)
        }
        
    }

    static func unmount(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await FileManager.default.unmountVolume(
            at: url,
            options: [.withoutUI]
        )
    }
}

