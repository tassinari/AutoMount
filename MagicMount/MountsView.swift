//
//  ContentView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/24/25.
//

import SwiftUI
import AppKit
import ServiceManagement

@Observable final class MountsViewModel{
    private var unmountNote : NSObjectProtocol?
    private var mountNote : NSObjectProtocol?
    
    deinit {
        if let unmountNote = unmountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(unmountNote)
        }
        if let mountNote = mountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(mountNote)
        }
    }
    @MainActor init() {
        
        
        let loginItem = SMAppService.loginItem(
            identifier: "org.tassinari.MagicMount.MagicMountBackground"
        )
        Task{
            try loginItem.register()
        }

        mountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            self?.refresh()
        }
        unmountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) {[weak self] note in
            self?.refresh()
           
        }
    }
   
    func refresh(){
        let connected = Set(MountInfo.mountedVolumes().filter({$0.type != "file"}))
        let managed = Set(StorageManager().mounts ?? [])
        let merged = connected.union(managed)
        mounts = Array(merged)
    }
    var mounts: [Share] = []


}

struct MountsView: View {
    @Environment(\.openWindow) var openWindow
    private var model: MountsViewModel = MountsViewModel()
    @State private var viewInTabBar: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            HStack {
                Text("Shares")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack{
                    Toggle("View in Tab Bar", isOn: $viewInTabBar)
                        .toggleStyle(.switch)
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .bottom
            )

            // MARK: - List
            SharesListView(shares: model.mounts)
           

            // MARK: - Bottom Bar
            HStack {
                Button {
                    addModel()
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .top
            )
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func addModel() {
        openWindow(id: MounterConstants.newMountWindowID)
    }
}

#Preview {
    MountsView()
}
