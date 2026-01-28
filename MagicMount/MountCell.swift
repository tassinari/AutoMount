//
//  MountCell.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/1/26.
//

import SwiftUI
import libMounter

struct MountCell: View {
    @Bindable var model: MountCellViewModel
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack(alignment: .center) {
                        driveIcon
                        Text(model.share.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text(model.share.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                if model.shouldShowOpenIcon {

                    Button {
                        model.share.open()
                    } label: {
                        Text(model.share.mountPoint)
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            HStack {
                Toggle("Auto-mount", isOn: $model.autoMount)
                    .toggleStyle(.switch)
                    .fixedSize()
                Spacer()
                Button {
                    model.mountUnmountPressed()
                } label: {
                    mountButtonLabel
                }
               // .buttonStyle(.glass)
                .disabled(model.shouldDisableMountBoutton)

            }

        }
        .padding()
    }
    var driveIcon: some View {
        switch model.share.connected {
        case .mounted, .unmounting:
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.green)
        case .unmounted, .mounting:
            Image(systemName: "externaldrive.badge.xmark")
                .font(.title2)
                .foregroundStyle(.gray)
        }
    }
    @ViewBuilder var mountButtonLabel: some View {
        switch model.share.connected {
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
    SharesListView(shares: PreviewData.mockShares)
    //    MountCell(model: MountCellModel(share: Share(user: "", password: "", url: URL(string: "smb://127.0.0.1/photos")!, name: "Photos", mountPoint: "/Volumes/photos", managed: true, connected: true)))
    //        .frame(width: 400, height: 150)
}
