
import Foundation
import NetFS

public enum MountError: Error{
    case badURL, noMountData
}
/// Errors:
///  os errors are defined in <sys/errno.h>
public enum MountResponse{
    case genericError(Error)
    case success([String])
    case authenticationError
    case cannotFindHost
    case timeout
    case noSuchFileOrDirectory
    case connectionRefused
    case alreadyMounted
   
}

public struct MountInfo{
    public static func mountedVolumes() -> [Share] {
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
            //DOnt include main hd
            if mount == "/"{
                continue
            }
            result.append(Share(user: "", password: "", url: remote, name: name, mountPoint: mount, managed: false, connected: true))
        }
        return result
    }
    
    public static func isVolumeMounted(at local: URL) -> Bool {
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
            if url.relativePath == local.relativePath { return true }
        }
        return false
    }
}

public struct MountData{
    public let scheme: String
    public let host: String
    public let port : Int?
    public let user: String?
    public let password: String?
    public let shareName: String
    
    public var url: URL{
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
    public func mount() async throws -> MountResponse {
       
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
                    let arrayRef: CFArray = unmanaged.takeUnretainedValue()
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

    public static func unmount(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await FileManager.default.unmountVolume(
            at: url,
            options: [.withoutUI]
        )
    }
}

