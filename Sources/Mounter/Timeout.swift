//
//  Timeout.swift
//  libMounter
//
//  Bounds work that touches a network filesystem, so an unreachable server
//  can never freeze a caller indefinitely.
//

import Foundation

/// Thrown by ``withTimeout(seconds:operation:)`` when the operation outlives its budget.
public struct TimeoutError: Error, Equatable, Sendable {
    /// The budget, in seconds, that the operation exceeded.
    public let seconds: TimeInterval
    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }
}

/// Runs `operation`, throwing ``TimeoutError`` if it does not finish within `seconds`.
///
/// The losing task is cancelled, but note that cancellation is cooperative: a thread already
/// blocked inside an uninterruptible syscall (`stat` on a dead NFS/SMB mount, say) keeps
/// occupying its thread until the kernel gives up. What this guarantees is that *the caller*
/// stops waiting — which is what keeps the UI responsive.
///
/// - Parameters:
///   - seconds: The time budget. Must be greater than zero.
///   - operation: The work to bound.
/// - Returns: The operation's value, if it completed in time.
/// - Throws: ``TimeoutError`` on expiry, or whatever `operation` threw.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError(seconds: seconds)
        }

        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TimeoutError(seconds: seconds)
        }
        return result
    }
}
