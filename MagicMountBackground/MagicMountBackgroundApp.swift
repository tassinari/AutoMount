//
//  MagicMountBackgroundApp.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI
import Network
import libMounter

@main
struct MagicMountBackgroundApp: App {
    let model = Model()
    @AppStorage("showMenuInBar",  store: UserDefaults(suiteName: "group.org.tassinari.magicmount")) private var showMenuBar = true
  
    var body: some Scene {
        MenuBarExtra("Magic Mount", systemImage: "externaldrive", isInserted: $showMenuBar) {
            ContentView(model: model.store)
        }
        .menuBarExtraStyle(.window)
    }
}

class Model{
    let store = ShareDataModel(storage: StorageManager())
    let remounter = Remounter()
    let detector: Detector = Detector()
    let queue = DispatchQueue(label: "MagicMount NetworkMonitor")
    
    init(){
        detector.listen(self)
    }
    
}

extension Model: DetectorDelegate{
    func didDetectEvent(_ event: DetectorEvent) {
        switch event{
            
        case .network:
            debug("Network event")
            Task{
                await remounter.checkAndRemount()
            }
            
        case .sleep:
            debug("Sleep event")
        case .volume:
            Task{
                await store.load()
            }
            
        }
        
    }
    
    
}
extension ShareDataModel{
    func openApp(){
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.tassinari.MagicMount"){
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}
