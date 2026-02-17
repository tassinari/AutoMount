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
    let store: ShareDataModel
    let remounter: Remounter
    let detector: Detector
    let queue = DispatchQueue(label: "MagicMount NetworkMonitor")
    private let defaults: UserDefaults
    private var periodicTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    convenience init() {
        let defaults = UserDefaults(suiteName: "group.org.tassinari.magicmount") ?? .standard
        self.init(defaults: defaults)
    }

    init(defaults: UserDefaults, remounter: Remounter? = nil, detector: Detector? = nil, storage: Storage? = nil) {
        self.defaults = defaults
        let resolvedStorage = storage ?? StorageManager()
        self.store = ShareDataModel(storage: resolvedStorage)
        self.detector = detector ?? Detector()

        let debounce = defaults.object(forKey: Constant.networkDebounceKey) as? Double ?? Constant.networkDebounceDefault
        self.remounter = remounter ?? Remounter(debounceSeconds: debounce, storage: resolvedStorage)

        self.detector.networkDebounceInterval = debounce
        self.detector.listen(self)

        startPeriodicTimer()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            self?.defaultsDidChange()
        }
    }

    deinit {
        periodicTimer?.invalidate()
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func defaultsDidChange() {
        let debounce = defaults.object(forKey: Constant.networkDebounceKey) as? Double ?? Constant.networkDebounceDefault
        detector.networkDebounceInterval = debounce
        Task {
            await remounter.setDebounce(debounce)
        }

        startPeriodicTimer()
    }

    private func startPeriodicTimer() {
        periodicTimer?.invalidate()
        let minutes = defaults.object(forKey: Constant.periodicRemountKey) as? Double ?? Constant.periodicRemountDefault
        let interval = minutes * 60
        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.remounter.checkAndRemount()
            }
        }
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

        case .wake:
            debug("Wake event")
            Task{
                await remounter.checkAndRemount()
            }
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
