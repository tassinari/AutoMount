//
//  Share.swift
//  AutoMount
//
//  Created by Mark Tassinari on 1/14/26.
//

import Foundation

/// A network share representing a mountable SMB, AFP, or NFS volume.
///
/// `Share` is the core model type in libMounter. It is immutable and value-typed — state transitions
/// (e.g. mounting, unmounting) produce new `Share` instances via copy methods rather than mutating in place.
///
/// Conforms to `Codable` for JSON persistence, `Sendable` for safe use across concurrency domains,
/// and `Hashable`/`Identifiable` for use in SwiftUI lists and sets.
public struct Share: Codable,Sendable {

    //FIXME: make this failable if URL does not conform to smb/afp/nfs??
    /// Creates a new share.
    ///
    /// - Parameters:
    ///   - url: The remote URL of the share (e.g. `smb://server/share`).
    ///   - name: An optional display name for the share.
    ///   - mountPoint: The local filesystem path where the share is (or will be) mounted.
    ///   - managed: Whether this share is user-managed and persisted to storage.
    ///   - connected: The current connection state of the share.
    public init( url: URL, name: String?, mountPoint: String?, managed: Bool, connected: ConnectionState) {
        self.url = url
        self.name = name
        self.mountPoint = mountPoint
        self.managed = managed
        self.connected = connected
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        mountPoint = try container.decodeIfPresent(String.self, forKey: .mountPoint)
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
    
    /// The remote URL of the share (e.g. `smb://server/share`, `afp://server/volume`, `nfs://server/export`).
    public let url : URL
    /// An optional display name for the share.
    public let name: String?
    /// The local filesystem path where the share is mounted, or `nil` if unknown.
    public let mountPoint: String?
    /// Whether this share is user-managed (persisted to storage) or system-detected.
    public let managed : Bool
    /// The current connection state of the share.
    public let connected : ConnectionState
    /// The URL scheme (e.g. `"smb"`, `"afp"`, `"nfs"`), derived from ``url``.
    public var  type: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme ?? ""
    }
    

    /// Keys used for JSON encoding and decoding of a ``Share``.
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
    /// Returns a new share with its state set to ``ConnectionState/mounting``.
    ///
    /// Use this to indicate a mount operation is in progress. All other properties are preserved.
    public var mountingCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .mounting)
    }
    /// Returns a new share with its state set to ``ConnectionState/unmounting``.
    ///
    /// Use this to indicate an unmount operation is in progress. All other properties are preserved.
    public var unmountingCopy : Share {
        Share( url: url, name: name, mountPoint: mountPoint, managed: managed, connected: .unmounting)
    }
}
extension Share {
    
    internal var mountData : MountData?{
        if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),let scheme = comp.scheme, let host = comp.host{
            return MountData(scheme: scheme , host: host, port: comp.port, path: comp.path)
        }
        return nil
    }
}
/// Identity, equality, and hashing for `Share`.
///
/// The ``id`` is composed of the URL, managed flag, and connection state so that SwiftUI
/// can detect state changes and update the UI accordingly.
extension Share: Hashable, Identifiable{
    /// A unique identifier composed of the URL, managed flag, and connection state.
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
    /// Returns `true` if this share points to the same remote resource as `other`.
    ///
    /// Compares the host, path, and scheme components of the URLs, ignoring connection state and managed flag.
    public func sameURL(as other: Share) -> Bool {
        return url.host == other.url.host && url.path() == other.url.path() && url.scheme == other.url.scheme
    }
}
