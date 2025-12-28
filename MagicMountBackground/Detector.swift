//
//  Detector.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/28/25.
//

import Foundation
import Network



class Detector{
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "MagicMount NetworkMonitor")
    
    init(){
        
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
              
                debug("Network available")
            } else {
                debug("Network unavailable")
            }

            if path.usesInterfaceType(.wifi) {
                debug("Using Wi-Fi")
            }

            if path.usesInterfaceType(.wiredEthernet) {
                debug("Using Ethernet")
            }
        }

        monitor.start(queue: queue)
    }
    
    
}
