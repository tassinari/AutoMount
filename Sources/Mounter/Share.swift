//
//  Share.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/14/26.
//

import Foundation
import AppKit



@Observable public class Share: Codable{
    
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
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let u = try? container.decode(String.self, forKey: .user){
            user = u
        }
        if let p = try? container.decode(String.self, forKey: .password){
            password = p
        }
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        mountPoint = try container.decode(String.self, forKey: .mountPoint)
        managed = try container.decode(Bool.self, forKey: .managed)
        connected = try container.decode(ConnectionState.self, forKey: .connected)
    }
    public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user, forKey: .user)
            try container.encode(password, forKey: .password)
            try container.encode(url, forKey: .url)
            try container.encode(name, forKey: .name)
            try container.encode(mountPoint, forKey: .mountPoint)
            try container.encode(managed, forKey: .managed)
            try container.encode(connected, forKey: .connected)
    }
    
    public var user : String?
    public var password : String?
    public let url : URL
    public let name: String
    public let mountPoint: String
    public var  type: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme ?? ""
    }
    public var managed : Bool
    public var connected : ConnectionState
    
    public  enum CodingKeys: String, CodingKey {
        case user
        case password
        case url
        case name
        case mountPoint
        case managed
        case connected
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
   
    public func unmount() async throws{
        if connected == .unmounting{
            return
        }
        let url = URL(filePath: mountPoint)
        self.connected = .unmounting
        do{
            try await MountData.unmount(url: url)
            self.connected = .unmounted
        }catch{
            self.connected = .mounted
            throw error
        }
    }
    public func mount() async throws -> MountResponse{
        if connected != .unmounted{
            return .alreadyMounted
        }
        if let mountData{
            do{
                self.connected = .mounting
                let data =  try await mountData.mount()
                self.connected = .unmounted
                return data
            }catch{
                self.connected = .unmounted
                throw error
            }
        }
        throw MountError.noMountData
    }
}
extension Share: Hashable, Identifiable{
    public var id: String{
        return url.absoluteString
    }
    public static func == (lhs: Share, rhs: Share) -> Bool {
        guard let lcomp = URLComponents(url: lhs.url, resolvingAgainstBaseURL: false),
              let rcomp = URLComponents(url: rhs.url, resolvingAgainstBaseURL: false) else {return false}
        return lcomp.scheme == rcomp.scheme && lcomp.host == rcomp.host && lcomp.path == rcomp.path
        
    }
    public func hash(into hasher: inout Hasher) {
        guard let uRLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else{
            hasher.combine(id)
            return
        }
        hasher.combine(uRLComponents.scheme)
        hasher.combine(uRLComponents.host)
        hasher.combine(uRLComponents.path)
        
    }
}
//FIXME: move this to client
extension Share{
    public func open(){
        let url = URL(filePath: mountPoint)
        if FileManager.default.fileExists(atPath: url.path){
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        
    }
}
