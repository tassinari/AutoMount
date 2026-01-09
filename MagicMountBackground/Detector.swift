//
//  Detector.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/28/25.
//

import Foundation
import Network
import AppKit

struct MountEvent{
    enum MountType { case mounted, unmounted}
    let type : MountType
    let path : String?
}
enum DetectorEvent{
    case network
    case sleep
    case volume(MountEvent)
}

protocol DetectorDelegate: AnyObject{
    func didDetectEvent(_ event: DetectorEvent)
}

class Detector{
    
    private var unmountNote : NSObjectProtocol?
    private var mountNote : NSObjectProtocol?
    
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "MagicMount NetworkMonitor")
    var delegate : DetectorDelegate?
    init(){
        mountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            if let info = note.userInfo{
                self?.delegate?.didDetectEvent(.volume(MountEvent(type: .mounted, path: info["NSDevicePath"] as? String)))
            }
        }
        unmountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) {[weak self] note in
            if let info = note.userInfo{
                self?.delegate?.didDetectEvent(.volume(MountEvent(type: .unmounted, path: info["NSDevicePath"] as? String)))
            }
        }
    }
    deinit {
        if let unmountNote = unmountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(unmountNote)
        }
        if let mountNote = mountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(mountNote)
        }
    }
    func listen(_ delegate: DetectorDelegate){
        self.delegate = delegate
        monitor.pathUpdateHandler = { [weak self]path in
            if path.status == .satisfied {
                self?.delegate?.didDetectEvent(.network)
            } else {
                debug("Network unavailable")
            }
#if DEBUG
            if path.usesInterfaceType(.wifi) {
                debug("Using Wi-Fi")
            }
            if path.usesInterfaceType(.wiredEthernet) {
                debug("Using Ethernet")
            }
#endif
        }

        monitor.start(queue: queue)
    }
    
    
}
