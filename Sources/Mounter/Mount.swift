
import Foundation
import NetFS

public enum MountError: Error{
    case badURL, noMountData
}
/// Errors:
///  os errors are defined in <sys/errno.h>
public enum MountResponse : Sendable{
    case genericError(Error)
    case success(String?)
    case authenticationError
    case cannotFindHost
    case timeout
    case noSuchFileOrDirectory
    case connectionRefused
    case alreadyMounted
   
}
internal struct MountedVolumesData: Equatable{
    let name : String
    let remountURL : URL
    let path : String
    
    func equal(to: Share) -> Bool {
        return remountURL.scheme == to.url.scheme && remountURL.host == to.url.host && remountURL.path() == to.url.path()
    }
    var share: Share {
        return Share( url: remountURL, name: name, mountPoint: path, managed: false, connected: .mounted)
    }
}

internal struct MountInfo{
    static func mountedVolumes() -> [MountedVolumesData] {
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

        var result: [MountedVolumesData] = []
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
            result.append(MountedVolumesData(name: name, remountURL: remote, path: mount))
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
            if url.relativePath == local.relativePath { return true }
        }
        return false
    }
}

internal struct MountData{
    public let scheme: String
    public let host: String
    public let port : Int?
    public let path: String
    
    public var url: URL{
        get throws{
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.path = path.isEmpty ? "" : "/\(path)"
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
    
    internal func mount(ui: Bool = false) async throws -> MountResponse {
       
        let url = try self.url
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var cfArray: Unmanaged<CFArray>?
                let mountD = NSMutableDictionary()
                let optD = NSMutableDictionary()
                if !ui{
                    mountD.setValue(kNAUIOptionNoUI, forKey:kNAUIOptionKey)
                }
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
                    retVal =  .success(messages.first)
                    //
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
        
    }

    internal static func unmount(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await FileManager.default.unmountVolume(
            at: url,
            options: [.withoutUI]
        )
    }
}

