//
//  NetAuthAgentRestarter.swift
//  AutoMountBackground
//

import Foundation
import Network

/// Restarts the system agent that performs NetFS mounts.
protocol NetAuthAgentRestarting: Sendable {
    /// Ends the running agent so launchd starts a fresh one on the next mount request.
    /// - Returns: `true` if an agent was found and ended.
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
        for pid in pids {
            notice("Restarting \(Self.processName) (pid \(pid))")
            kill(pid, SIGTERM)
        }
        let deadline = Date() + gracePeriod
        var remaining = pids
        while !remaining.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            remaining = remaining.filter(Self.isRunning)
        }
        for pid in remaining {
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
            let once = ResumeOnceFlag()
            let finish: @Sendable (Bool) -> Void = { reachable in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: reachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
            connection.start(queue: queue)
        }
    }
}

/// Lets exactly one caller through, for resuming a continuation once.
private nonisolated final class ResumeOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
