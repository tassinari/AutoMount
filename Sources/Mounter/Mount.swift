
import Foundation
import NetFS

/// Errors thrown during mount URL construction or data preparation.
///
/// - ``badURL``: The URL could not be constructed from the share's components.
/// - ``noMountData``: The share's URL could not be decomposed into valid mount data.
public enum MountError: Error{
    case badURL, noMountData
}

/// The result of a NetFS mount operation.
///
/// OS-level error codes are defined in `<sys/errno.h>` and mapped to
/// descriptive cases for common failure modes.
public enum MountResponse : Sendable{
    /// An error not covered by the specific cases, wrapping the underlying `Error`.
    case genericError(Error)
    /// The mount succeeded. The associated value is the local mount path, if available.
    case success(String?)
    /// Authentication failed (e.g. invalid credentials).
    case authenticationError
    /// The remote host could not be reached.
    case cannotFindHost
    /// The connection timed out before the mount could complete.
    case timeout
    /// The remote share path does not exist on the server.
    case noSuchFileOrDirectory
    /// The server actively refused the connection.
    case connectionRefused
    /// The volume is already mounted at a local path.
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
            let local = values?.volumeIsLocal ?? true
            let name = values?.volumeName ?? url.lastPathComponent
            let mount = values?.path ?? "/"
            let remote = values?.volumeURLForRemounting ?? url
            if local{
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
            if !path.isEmpty, !path.hasPrefix("/"){
                components.path = "/\(path)"
            }else{
                components.path = path
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

