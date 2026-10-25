//
//  NetAuthAgentRestarter.swift
//  AutoMountBackground
//

import Foundation
import Network
import os

/// Restarts the system agent that performs NetFS mounts.
protocol NetAuthAgentRestarting: Sendable {
    /// Ends the running agent so launchd starts a fresh one on the next mount request.
    /// - Returns: `true` if an agent was found and signalled.
    func restart() async -> Bool
}

/// Checks whether a server accepts connections, without involving NetAuthSysAgent.
protocol ServerReachability: Sendable {
    func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool
}

/// Ends the current user's NetAuthSysAgent, the equivalent of `killall NetAuthSysAgent`.
///
/// The agent runs as the logged-in user and launchd relaunches it on demand, so no
/// privileges are needed. Mounted volumes are kernel mounts and are not affected.
///
/// Requires the app to be unsandboxed: App Sandbox blocks signals to other processes.
nonisolated struct NetAuthAgentRestarter: NetAuthAgentRestarting {
    static let processName = "NetAuthSysAgent"

    /// How long to wait after SIGTERM before sending SIGKILL. A wedged agent's main thread
    /// may never get to handle SIGTERM.
    let gracePeriod: TimeInterval

    init(gracePeriod: TimeInterval = 3) {
        self.gracePeriod = gracePeriod
    }

    func restart() async -> Bool {
        let pids = Self.pids(named: Self.processName, uid: getuid())
        guard !pids.isEmpty else {
            notice("No \(Self.processName) running for this user; nothing to restart")
            return false
        }
        var signalled: [pid_t] = []
        for pid in pids {
            notice("Restarting \(Self.processName) (pid \(pid))")
            if kill(pid, SIGTERM) == 0 {
                signalled.append(pid)
            } else {
                let code = errno
                notice("Could not signal \(Self.processName) (pid \(pid)): \(String(cString: strerror(code)))")
            }
        }
        guard !signalled.isEmpty else { return false }
        let deadline = Date() + gracePeriod
        var remaining = signalled
        while !remaining.isEmpty, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            remaining = remaining.filter(Self.isRunning)
        }
        // A pid can be reused during the grace period; only kill one that is still the agent.
        let stillAgent = Set(Self.pids(named: Self.processName, uid: getuid()))
        for pid in remaining where stillAgent.contains(pid) {
            notice("\(Self.processName) (pid \(pid)) ignored SIGTERM; sending SIGKILL")
            kill(pid, SIGKILL)
        }
        return true
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    /// The processes owned by `uid` whose command name is `name`.
    static func pids(named name: String, uid: uid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: uid)]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Leave room for processes started between the two calls.
        size += 16 * MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return procs.prefix(count).compactMap { proc in
            var comm = proc.kp_proc.p_comm
            let command = withUnsafeBytes(of: &comm) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            return command == name ? proc.kp_proc.p_pid : nil
        }
    }
}

/// Opens a TCP connection to the server and reports whether it became ready in time.
nonisolated struct TCPServerReachability: ServerReachability {
    func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "AutoMount reachability")
        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Bool) -> Void = { reachable in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: reachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                // `.waiting` means no route or a refused connection; it would only retry until the deadline.
                case .waiting, .failed, .cancelled: finish(false)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
            connection.start(queue: queue)
        }
    }
}
