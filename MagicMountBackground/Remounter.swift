//
//  Remounter.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 1/4/26.
//

import Foundation

actor Remounter{
    init(debounceSeconds : TimeInterval = 20){
        self.debounceSeconds = debounceSeconds
        callDate = .now
    }
    private var debounceSeconds: TimeInterval
    private var callDate: Date
    
    func checkAndRemount() async{
        if Date.now.timeIntervalSince(callDate) < debounceSeconds{
            await debug("Cache still valid, not remounting")
            return
        }
        callDate = .now
        let mountedVolumes = await MountInfo.mountedVolumes()
        let manager = await StorageManager()
        for mount in await manager.mounts ?? []{
            if !mountedVolumes.contains(mount){
                await notice("\(mount.name) is not connected, connecting..")
                guard let md = await mount.mountData else {
                    await error("could not get mountdata for \(mount.name)")
                    return
                }
                do{
                    switch try await md.mount(){
                        
                    case .genericError(let e):
                        await error("Generic error in mount attempt: \(String(describing: e))")
                    case .success(let mp):
                        await notice("Success, \(mount.name) is mounted on \(mp.first ?? "unknown")")
                    case .authenticationError:
                        await notice("Mount failure for \(mount.name): auth error")
                    case .cannotFindHost:
                        await notice("Mount failure for \(mount.name): no host")
                    case .timeout:
                        await notice("Mount failure for \(mount.name): timeout")
                    case .noSuchFileOrDirectory:
                        await notice("Mount failure for \(mount.name): no such file or directory")
                    case .connectionRefused:
                        await notice("Mount failure for \(mount.name): connection refused")
                    case .alreadyMounted:
                        await notice("Mount failure for \(mount.name): already mounted")
                    }
                }catch {
                    await MagicMountBackground.error("Mount(\(mount.name) threw:  \(String(describing: error))")
                }
            }else{
                await notice("\(mount.name) connected, not attempting remount")
            }
        }
    }
}
