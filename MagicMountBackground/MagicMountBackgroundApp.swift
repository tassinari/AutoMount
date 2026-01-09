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
            ContentView(model: model.menuModel)
        }
        .menuBarExtraStyle(.window)
    }
}

class Model{
    let menuModel = MenuModel()
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
            menuModel.refresh()
        }
        
    }
    
    
}
