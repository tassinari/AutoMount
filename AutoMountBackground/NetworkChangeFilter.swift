//
//  NetworkChangeFilter.swift
//  AutoMountBackground
//

import Foundation
import Network

/// The parts of a network path that decide whether shares could have become reachable.
nonisolated struct NetworkSnapshot: Equatable, Sendable {
    /// Whether the path can carry traffic and resolve names.
    let isUsable: Bool
    /// Interface names in the order the system prefers them, e.g. `["en0", "utun3"]`.
    let interfaces: [String]
    /// Gateways in the order the system reports them.
    let gateways: [String]
}

extension NetworkSnapshot {
    init(_ path: NWPath) {
        self.init(isUsable: path.status == .satisfied && path.supportsDNS,
                  interfaces: Self.uniqued(path.availableInterfaces.map(\.name)),
                  gateways: Self.uniqued(path.gateways.map { "\($0)" }))
    }

    /// The system can list the same interface more than once (`en0` twice on Wi-Fi), so
    /// keep the first of each to stop the count alone from looking like a change.
    static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

/// Decides which path updates are worth a remount pass.
///
/// `NWPathMonitor` calls its handler for changes that do not affect reachability, such as
/// link quality or DNS health. On 2026-10-20 a Mac with weak Wi-Fi received an update
/// every 12-20 seconds from 08:54 to 18:54 while en0 stayed connected. Each one started
/// a remount pass, and the mounts those passes cancelled left empty `/Volumes/<name>-N`
/// folders behind.
///
/// A path update counts only when the network becomes usable or, while usable, its
/// interfaces or gateways change, as when joining another network or a VPN coming up.
nonisolated struct NetworkChangeFilter: Sendable {
    private var last: NetworkSnapshot?

    /// Records `snapshot` and returns whether it is a change worth reporting.
    mutating func shouldReport(_ snapshot: NetworkSnapshot) -> Bool {
        defer { last = snapshot }
        guard snapshot.isUsable else { return false }
        return snapshot != last
    }
}

/// Wraps `NetworkChangeFilter` with a count of the updates it filtered out, for logging.
nonisolated struct NetworkChangeTracker: Sendable {
    private var filter = NetworkChangeFilter()
    private var ignoredCount = 0

    /// Returns the number of updates ignored since the last reported change when
    /// `snapshot` is reported, or `nil` when it is filtered out.
    mutating func report(_ snapshot: NetworkSnapshot) -> Int? {
        guard filter.shouldReport(snapshot) else {
            ignoredCount += 1
            return nil
        }
        defer { ignoredCount = 0 }
        return ignoredCount
    }
}
