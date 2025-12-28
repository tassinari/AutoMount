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
    init() {
        
        
        let loginItem = SMAppService.loginItem(
            identifier: "org.tassinari.MagicMount.MagicMountBackground"
        )
        Task{
            try loginItem.register()
        }
       
        refresh()
    }
   
    func refresh(){
        if let mnts = StorageManager().mounts {
            mounts = mnts
        }else{
            //FIXME: logger
        }
    }
    var mounts: [Share] = []
}

struct MountsView: View {
    @Environment(\.openWindow) var openWindow
    @State private var viewInTabBar = false
    private var model: MountsViewModel = MountsViewModel()

    // Keep references to windows we open so they aren't deallocated immediately
    @State private var newMountWindows: [NSWindow] = []

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            HStack {
                Text("Shares")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Toggle("View in Tab Bar", isOn: $viewInTabBar)
                    .toggleStyle(.switch)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .bottom
            )

            // MARK: - List
            List {
                ForEach(model.mounts, id: \.self) { mount in
                    Text(mount.url)
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)

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
