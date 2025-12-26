
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
        case ENOENT:
            return .noSuchFileOrDirectory
            
        default:
            return .genericError(NSError(domain: "NetFS", code: Int(response), userInfo: nil))
        }
    }
}

