//
//  NetAuthAgentWatchdog.swift
//  AutoMountBackground
//

import Foundation

/// Decides when NetAuthSysAgent looks wedged and should be restarted.
///
/// On 2026-10-21 NetAuthSysAgent hung at 03:08 inside an SMB login (`LsarGetUserName`,
/// waiting forever on the server's reply). Its main thread then blocked behind that call,
/// so every later mount request timed out, even though the server answered on port 445
/// the whole time. Cancelling a request does not free the agent; only restarting it does.
///
/// Mount timeouts are counted per server. Once a server reaches `timeoutThreshold` in a row,
/// the caller checks that the server is reachable and, if it is, restarts the agent.
/// Restarts are limited to one per `cooldown`, so a server that is just slow does not get
/// the agent killed over and over.
nonisolated struct NetAuthAgentWatchdog {
    let timeoutThreshold: Int
    let cooldown: TimeInterval
    private var consecutiveTimeouts: [String: Int] = [:]
    private var lastRestart: Date?

    init(timeoutThreshold: Int = 3, cooldown: TimeInterval = 15 * 60) {
        self.timeoutThreshold = timeoutThreshold
        self.cooldown = cooldown
    }

    /// Records a mount timeout for `server`.
    mutating func recordTimeout(_ server: String) {
        consecutiveTimeouts[server, default: 0] += 1
    }

    /// Records any outcome the agent actually answered, which shows it is not wedged.
    mutating func recordAnswer(_ server: String) {
        consecutiveTimeouts[server] = nil
    }

    /// Whether `server` has timed out often enough, and long enough after the last restart,
    /// to justify restarting the agent.
    func shouldRestart(for server: String, now: Date) -> Bool {
        guard consecutiveTimeouts[server, default: 0] >= timeoutThreshold else { return false }
        guard let lastRestart else { return true }
        return now.timeIntervalSince(lastRestart) >= cooldown
    }

    /// Records a restart attempt and starts counting from zero for every server.
    mutating func recordRestart(now: Date) {
        lastRestart = now
        consecutiveTimeouts.removeAll()
    }

    /// A key that groups shares by the server and port they mount from.
    static func serverKey(for url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return "\(host):\(port(for: url))"
    }

    /// The port a share's server listens on: the URL's own, or the scheme's default.
    static func port(for url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "nfs" ? 2049 : 445
    }
}
