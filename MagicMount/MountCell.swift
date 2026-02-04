//
//  MountCell.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/1/26.
//

import SwiftUI
import libMounter

struct MountCell: View {
    let share : Share
    @Environment(ShareDataModel.self) var model
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack(alignment: .center) {
                        driveIcon
                        Text(share.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text(share.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                if share.connected == .mounted {

                    Button {
                        share.open()
                    } label: {
                        Text(share.mountPoint)
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            HStack {
                Toggle("Auto-mount", isOn: Binding<Bool>.constant(true))
                    .toggleStyle(.switch)
                    .fixedSize()
                Spacer()
                Button {
                    Task{
                        if share.connected == .mounted{
                           try await model.unmount(share)
                        }else{
                            try await model.mount(share)
                        }
                    }
                   
                    //model.mountUnmountPressed()
                } label: {
                    mountButtonLabel
                }
               // .buttonStyle(.glass)
                //.disabled(model.shouldDisableMountBoutton)

            }

        }
        .padding()
    }
    var driveIcon: some View {
        Image(systemName: Constant.driveIconConnected)
            .font(.title2)
            .foregroundStyle(.green)
    }

    @ViewBuilder var mountButtonLabel: some View {
        switch share.connected {
        case .mounted:
            Image(systemName: "eject")
                .foregroundStyle(.gray)
                .font(.title2)
        case .unmounted:
            Text("Mount")
        case .unmounting, .mounting:
            ProgressView()
                .controlSize(.mini)
                //.frame(width: 16, height: 16)

        }
    }
}

#Preview {
    SharesListView()
        .environment(MockStore.store)
    //    MountCell(model: MountCellModel(share: Share(user: "", password: "", url: URL(string: "smb://127.0.0.1/photos")!, name: "Photos", mountPoint: "/Volumes/photos", managed: true, connected: true)))
    //        .frame(width: 400, height: 150)
}
