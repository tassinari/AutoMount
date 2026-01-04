//
//  MagicMountBackgroundApp.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI
import Network

@main
struct MagicMountBackgroundApp: App {
    let model = Model()
    @AppStorage("showMenuInBar",  store: UserDefaults(suiteName: "N2Z455V6H8.org.tassinari")) private var showMenuBar = true
  
    var body: some Scene {
        MenuBarExtra("Magic Mount", systemImage: "externaldrive", isInserted: $showMenuBar) {
          ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

class Model{
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
