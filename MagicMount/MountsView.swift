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
        refresh()
        mountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            if let info = note.userInfo{
                self?.updateConnection(mounted: true, dict: info)
            }
        }
        unmountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) {[weak self] note in
            if let info = note.userInfo{
                self?.updateConnection(mounted: false, dict: info)
            }
        }
    }
    /// updates Share from a user info dictionary passed by the mount/unmount notification
    func updateConnection(mounted: Bool, dict: [AnyHashable: Any]){
        if  let path = dict["NSDevicePath"] as? String{
            var found = false
            for mount in mounts{
                if mount.mountPoint == path{
                    found = true
                    withAnimation {
                        mount.connected = mounted ? .mounted : .unmounted
                    }
                }
            }
            if !found{
                self.refresh()
            }
        }
        else{
            self.refresh()
        }
    }
   
    func refresh(){
        mounts = StorageManager().fullMountList ?? []
    }
    var mounts: [Share] = []


}

struct MountsView: View {
    @Environment(MountsViewModel.self) var model
    @State private var showNew : Bool = false
    @AppStorage("showMenuInBar",  store: UserDefaults(suiteName: "group.org.tassinari.magicmount")) private var showMenuBar = true
    
    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            HStack {
                Text("Shares")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack{
                    Toggle("Menu Bar Icon", isOn: $showMenuBar)
                        .toggleStyle(.switch)
                   
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
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title)
                }
                .buttonStyle(.borderless)

                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title)
                        
                   
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .top
            )
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showNew, content: {
            NewMount()
        })
    }
}

#Preview {
    MountsView()
}
