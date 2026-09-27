//
//  Remounter.swift
//  AutoMountBackground
//
//  Created by Mark Tassinari on 1/4/26.
//

import Foundation
import libMounter

actor Remounter{
    init(debounceSeconds : TimeInterval = 20, storage: Storage = StorageManager()){
        self.debounceSeconds = debounceSeconds
        self.storage = storage
    }
    internal var debounceSeconds: TimeInterval
    private let storage : Storage
    private var pendingTask: Task<Void, Never>?
    /// The remount pass currently running, if any.
    ///
    /// Cancelling `pendingTask` only stops a pass that is still in its debounce sleep; once
    /// `reconnectAll()` has started it runs to completion. And because this is an actor,
    /// it keeps accepting events while that pass is suspended in a mount -- which, while the
    /// Mac is asleep, can be for hours. Without this, every later event started another pass
    /// alongside it, and when the network came back they all mounted the same shares at once.
    private var reconnectTask: Task<Void, Never>?
    /// Set when an event's debounce expires while a pass is running. That pass then runs
    /// once more when it finishes, so the event is not lost -- but however many events
    /// arrive, at most one follow-up pass is queued.
    private var followUpRequested = false

    func setDebounce(_ seconds: TimeInterval) {
        debounceSeconds = seconds
    }

    func checkAndRemount(_ event: DetectorEvent) async {
        notice("remount event: \(event)")
        if pendingTask != nil {
            notice("Debounced: rescheduling")
        }
        pendingTask?.cancel()
        let seconds = debounceSeconds
        let task = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            await runReconnect()
        }
        pendingTask = task
        await task.value
    }
    /// Runs `reconnectAll()`, making sure only one pass is ever in progress.
    private func runReconnect() async {
        if let running = reconnectTask {
            notice("Remount pass already running; queueing a follow-up pass")
            followUpRequested = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                self.followUpRequested = false
                await self.reconnectAll()
            } while self.followUpRequested
            self.reconnectTask = nil
        }
        reconnectTask = task
        await task.value
    }

    /// Clears any stale mounts, then remounts every managed share that is not connected.
    ///
    /// Deliberately *not* `@MainActor`: nothing here touches UI, and hopping to the main actor
    /// meant the mount work and the volume enumeration it awaits were serialised behind the
    /// main thread — so an unreachable server froze the whole app rather than just this task.
    private func reconnectAll() async{
        // Detach dead mount points first. Otherwise `fullMountList` reports a stale mount as
        // connected (so nothing gets remounted), and any remount that does happen lands on a
        // duplicate mount point such as `/Volumes/media-1`.
        await storage.clearStaleMounts()
        let shares = await storage.fullMountList()
        for share in shares{
            if share.managed{
                let name = share.name ?? "--"
                if share.connected == .unmounted{
                    notice("\(name) is not connected, connecting..")
                    do{
                        switch try await storage.mount(share, ui: false){
                            
                        case .genericError(let e):
                            error("Generic error in mount attempt: \(String(describing: e))")
                        case .success(let mp):
                            notice("Success, \(name) is mounted on \(mp ?? "unknown")")
                        case .authenticationError:
                            notice("Mount failure for \(name): auth error")
                        case .cannotFindHost:
                            notice("Mount failure for \(name): no host")
                        case .timeout:
                            notice("Mount failure for \(name): timeout")
                        case .noSuchFileOrDirectory:
                            notice("Mount failure for \(name): no such file or directory")
                        case .connectionRefused:
                            notice("Mount failure for \(name): connection refused")
                        case .alreadyMounted:
                            notice("Mount failure for \(name): already mounted")
                        case .duplicateRejected(let path):
                            notice("Rejected duplicate mount of \(name) at \(path); already mounted elsewhere")
                        }
                    }catch {
                        AutoMountBackground.error("Mount(\(name)) threw:  \(String(describing: error))")
                    }
                }else{
                     notice("\(name) connected, not attempting remount")
                }
            }
        }
    }
}
