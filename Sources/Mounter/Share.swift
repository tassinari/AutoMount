//
//  Share.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/14/26.
//

import Foundation


public struct Share: Codable,Sendable {
    
    //FIXME: make this failable if URL does not conform to smb/afp/nfs??
    public init(user: String?, password: String?, url: URL, name: String, mountPoint: String, managed: Bool, connected: ConnectionState) {
        self.user = user
        self.password = password
        self.url = url
        self.name = name
        self.mountPoint = mountPoint
        self.managed = managed
        self.connected = connected
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        mountPoint = try container.decode(String.self, forKey: .mountPoint)
        managed = try container.decode(Bool.self, forKey: .managed)
        connected = try container.decode(ConnectionState.self, forKey: .connected)
        do{
            let creds = try Keychain().retrieve(url: url)
            user = creds.user
            password = creds.password
        }catch{
            user = nil
            password = nil
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(managed, forKey: .managed)
        try container.encode(connected, forKey: .connected)
        
        //dont save user pass in this object, save in keychain, pull out in decoder
        if let user, let password {
            do{
                try Keychain().save(user: user, password: password, url: url)
            }catch{
                libMounter.error("Encode keychain error: \(String(describing: error))")
            }
        }
       
        
    }
    
    public let user : String?
    public let password : String?
    public let url : URL
    public let name: String
    public let mountPoint: String
    public let managed : Bool
    public let connected : ConnectionState
    public var  type: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme ?? ""
    }
    
    
    public  enum CodingKeys: String, CodingKey {
        case url
        case name
        case mountPoint
        case managed
        case connected
    }
    
    internal var managedCopy : Share {
        Share(user: user, password: password, url: url, name: name, mountPoint: mountPoint, managed: true, connected: connected)
    }
    internal var unmanagedCopy : Share {
        Share(user: user, password: password, url: url, name: name, mountPoint: mountPoint, managed: false, connected: connected)
    }
    internal var mountedCopy : Share {
        Share(user: user, password: password, url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .mounted)
    }
    internal var unmountedCopy : Share {
        Share(user: user, password: password, url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .unmounted)
    }
    public var mountingCopy : Share {
        Share(user: user, password: password, url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .mounting)
    }
    public var unmountingCopy : Share {
        Share(user: user, password: password, url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .unmounting)
    }
}
//FIXME: put mount unmount into an actor to preserve state access
extension Share {
    
    internal var mountData : MountData?{
        if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),let scheme = comp.scheme, let host = comp.host{
            return MountData(scheme: scheme , host: host, port: comp.port, user: comp.user, password: comp.password, shareName: name)
        }
        return nil
    }
}
extension Share: Hashable, Identifiable{
    public var id: String{
        let managed = managed ? "1" : "0"
        return url.absoluteString + ":" + managed + ":" + connected.description
    }
    public static func == (lhs: Share, rhs: Share) -> Bool {
       return lhs.id == rhs.id
        
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
