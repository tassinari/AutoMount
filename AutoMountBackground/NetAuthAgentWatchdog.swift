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
/// One agent serves every server, so timeouts are counted across all shares: any mount the
/// agent answers shows it is alive and resets the count. Once `timeoutThreshold` timeouts
/// arrive in a row, the caller checks that the server is reachable and, if it is, restarts
/// the agent. The caller also clears the count on wake, so timeouts from before a sleep do
/// not carry over.
///
/// Restarts are limited to one per cooldown. The cooldown starts at `cooldown` and doubles
/// after each restart that is not followed by a successful mount, up to `maximumCooldown`:
/// if the server itself is what hangs, a fresh agent wedges again and restarting it every
/// few minutes would not help.
nonisolated struct NetAuthAgentWatchdog {
    let timeoutThreshold: Int
    let cooldown: TimeInterval
    let maximumCooldown: TimeInterval
    private var consecutiveTimeouts = 0
    private var lastRestart: Date?
    private var restartsWithoutSuccess = 0

    init(timeoutThreshold: Int = 3,
         cooldown: TimeInterval = 15 * 60,
         maximumCooldown: TimeInterval = 4 * 60 * 60) {
        self.timeoutThreshold = timeoutThreshold
        self.cooldown = cooldown
        self.maximumCooldown = maximumCooldown
    }

    /// Records a mount that got no answer in time.
    mutating func recordTimeout() {
        consecutiveTimeouts += 1
    }

    /// Records a mount the agent answered, which shows it is not wedged. Only a successful
    /// mount shows that a restart helped.
    mutating func recordAnswer(success: Bool) {
        consecutiveTimeouts = 0
        if success {
            restartsWithoutSuccess = 0
        }
    }

    /// Forgets the timeouts counted so far, keeping the restart history.
    mutating func resetTimeouts() {
        consecutiveTimeouts = 0
    }

    /// How long to wait after the last restart before allowing another.
    var currentCooldown: TimeInterval {
        let doublings = max(0, min(restartsWithoutSuccess - 1, 16))
        return min(cooldown * pow(2, Double(doublings)), maximumCooldown)
    }

    /// Whether enough timeouts arrived in a row, long enough after the last restart, to
    /// justify restarting the agent.
    func shouldRestart(now: Date) -> Bool {
        guard consecutiveTimeouts >= timeoutThreshold else { return false }
        guard let lastRestart else { return true }
        return now.timeIntervalSince(lastRestart) >= currentCooldown
    }

    /// Records a restart attempt and starts counting timeouts from zero.
    mutating func recordRestart(now: Date) {
        lastRestart = now
        restartsWithoutSuccess += 1
        consecutiveTimeouts = 0
    }
}
