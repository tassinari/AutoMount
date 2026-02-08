//
//  Share.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/14/26.
//

import Foundation


public struct Share: Codable,Sendable {
    
    //FIXME: make this failable if URL does not conform to smb/afp/nfs??
    public init( url: URL, name: String, mountPoint: String?, managed: Bool, connected: ConnectionState) {
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
      
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(managed, forKey: .managed)
        try container.encode(connected, forKey: .connected)
       
    }
    
    public let url : URL
    public let name: String
    public let mountPoint: String?
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
        Share( url: url, name: name, mountPoint: mountPoint, managed: true, connected: connected)
    }
    internal var unmanagedCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: false, connected: connected)
    }
    internal var mountedCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .mounted)
    }
    internal var unmountedCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .unmounted)
    }
    public var mountingCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .mounting)
    }
    public var unmountingCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .unmounting)
    }
}
//FIXME: put mount unmount into an actor to preserve state access
extension Share {
    
    internal var mountData : MountData?{
        if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),let scheme = comp.scheme, let host = comp.host{
            return MountData(scheme: scheme , host: host, port: comp.port, path: name)
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
