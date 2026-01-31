//
//  Share.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/14/26.
//

import Foundation
import AppKit

// @unchecked Sendable because of one mutable property cached snapshot, but that should be ok, only mutated in setters 
public final class Share: Codable, @unchecked Sendable {
    
    private let state : ShareState
    private var cachedSnapShot : ShareSnapshot
    public let url : URL
    public let name: String
    public let mountPoint: String
    public var type: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme ?? ""
    }
    
    //FIXME: make this failable if URL does not conform to smb/afp/nfs??
    public init(user: String?, password: String?, url: URL, name: String, mountPoint: String, managed: Bool, connected: ConnectionState) {
        self.url = url
        self.name = name
        self.mountPoint = mountPoint
        self.state = ShareState(user: user, password: password, managed: managed, connected: connected)
        self.cachedSnapShot = ShareSnapshot(user: user, password: password, managed: managed, connected: connected)
    }
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        mountPoint = try container.decode(String.self, forKey: .mountPoint)
        
        let snap = try container.decode(ShareSnapshot.self, forKey: .snapshot)
        self.state = ShareState(
            user: snap.user,
            password: snap.password,
            managed: snap.managed,
            connected: snap.connected
        )
        self.cachedSnapShot = snap
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(cachedSnapShot, forKey: .snapshot)
    }
   
    //MARK: mutable getters/setters
    func getUser() async -> String?{ await state.currentUser() }
    func getPassword() async -> String?{ await state.currentPassword() }
    func getManaged() async -> Bool{ await state.isManaged() }
    func getConnected() async -> ConnectionState{ await state.connection() }
    
    func setUser(_ user: String?) async{
        await state.setUser(user)
        cachedSnapShot = await state.snapshot()
    }
    func setPassword(_ pw: String?) async{
        await state.setPassword(pw)
        cachedSnapShot = await state.snapshot()
    }
    func setManaged(_ man: Bool) async{
        await state.setManaged(man)
        cachedSnapShot = await state.snapshot()
    }
    func setConnected(_ con: ConnectionState) async{
        await state.updateConnection(con)
        cachedSnapShot = await state.snapshot()
    }
}
extension Share{
    public  enum CodingKeys: String, CodingKey {
        case url
        case name
        case mountPoint
        case snapshot
    }
}
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

private actor ShareState {
    private var user: String?
    private var password: String?
    private var managed: Bool
    private var connected: ConnectionState

    init(user: String?, password: String?, managed: Bool, connected: ConnectionState) {
        self.user = user
        self.password = password
        self.managed = managed
        self.connected = connected
    }

    // Reads
    func currentUser() -> String? { user }
    func currentPassword() -> String? { password }
    func isManaged() -> Bool { managed }
    func connection() -> ConnectionState { connected }

    // Writes
    func setUser(_ newUser: String?) { user = newUser }
    func setPassword(_ newPassword: String?) { password = newPassword }
    func setManaged(_ flag: Bool) { managed = flag }
    func updateConnection(_ state: ConnectionState) { connected = state }

    // Snapshot for Codable/UI/Equality
    func snapshot() -> ShareSnapshot {
        ShareSnapshot(
            user: user,
            password: password,
            managed: managed,
            connected: connected
        )
    }
}

// A Sendable value type that mirrors the mutable bits
private struct ShareSnapshot: Sendable, Codable, Equatable {
    var user: String?
    var password: String?
    var managed: Bool
    var connected: ConnectionState
}
