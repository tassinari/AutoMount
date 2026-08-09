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
            await reconnectAll()
        }
        pendingTask = task
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
