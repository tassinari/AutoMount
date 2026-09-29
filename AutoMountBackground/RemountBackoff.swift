//
//  RemountBackoff.swift
//  AutoMountBackground
//

import Foundation

/// Spaces out remount attempts for shares whose mounts keep timing out.
///
/// Remount passes are triggered by network, wake and timer events. During dark wakes the
/// network flaps constantly, so on 2026-09-29 back-to-back passes sent well over a hundred
/// mount requests between 03:00 and 06:20. Every one timed out, and each timeout left a cancelled
/// request queued in a wedged NetAuthSysAgent. A share that times out now waits 1, 2, then
/// 4 minutes before the next attempt, capped at `maximumDelay`.
///
/// Only timeouts count. A missing host or a refused connection fails in milliseconds and says
/// nothing about NetFS being stuck, so those shares keep retrying on every event.
///
/// Times are wall-clock `Date`s, not uptime, so a wait keeps counting while the Mac sleeps.
nonisolated struct RemountBackoff {
    let initialDelay: TimeInterval
    let maximumDelay: TimeInterval
    private var entries: [String: Entry] = [:]

    private struct Entry {
        var consecutiveTimeouts: Int
        var retryAfter: Date
    }

    /// The default cap matches the background timer's cadence, so after a real wake a
    /// backed-off share is retried no later than the timer would have tried it anyway.
    init(initialDelay: TimeInterval = 60, maximumDelay: TimeInterval = 300) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    /// When `key` may next be attempted, or `nil` if it may be attempted at `now`.
    func retryAfter(_ key: String, now: Date) -> Date? {
        guard let entry = entries[key], entry.retryAfter > now else { return nil }
        return entry.retryAfter
    }

    /// Records a timeout for `key` and doubles its wait, up to `maximumDelay`.
    mutating func recordTimeout(_ key: String, now: Date) {
        let timeouts = (entries[key]?.consecutiveTimeouts ?? 0) + 1
        // Capping the exponent keeps the arithmetic finite however long the outage lasts.
        let delay = min(initialDelay * pow(2, Double(min(timeouts - 1, 16))), maximumDelay)
        entries[key] = Entry(consecutiveTimeouts: timeouts, retryAfter: now + delay)
    }

    /// Clears `key` after any outcome other than a timeout.
    mutating func reset(_ key: String) {
        entries[key] = nil
    }

    /// Clears every share, so all are retried at once. Called on a real wake: the user is
    /// back and expects the shares, and what went wrong overnight may have cleared.
    mutating func resetAll() {
        entries.removeAll()
    }
}
