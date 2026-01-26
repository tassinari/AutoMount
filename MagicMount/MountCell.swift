//
//  MountCell.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/1/26.
//

import SwiftUI
import libMounter

@Observable class MountCellModel {
    let share: Share
    let manageHandler: ((Share) -> Void)?
    let storage : Storage
    var autoMount: Bool {
        set {
            share.managed = newValue
            do {
                if newValue {
                    try storage.addMount(share)
                } else {
                    try storage.deleteMount(share)
                }
            } catch {
                MagicMount.error(
                    "Cell mount/unmount error: \(String(describing: error))"
                )
            }
        }
        get {
            return share.managed
        }
    }

    init(share: Share, storage: Storage = StorageManager() , handler: ((Share) -> Void)? = nil) {
        self.share = share
        self.manageHandler = handler
        self.storage = storage
    }

    func eject() {
        Task {
            do {
                try await share.unmount()
            } catch {
                MagicMount.error("unmount error : \(String(describing: error))")
            }
        }
    }
    
    func mount() {
        Task {
            do {
                switch try await share.mount() {
                case .success(_):
                    break
                default:
                    MagicMount.error("mount error, non success returned")
                }
            } catch {
                MagicMount.error("mount error : \(String(describing: error))")
            }
        }
    }
    
    func edit() {
        manageHandler?(share)
    }
    
    func mountUnmountPressed() {
        switch share.connected {
        case .mounted:
            eject()
        case .unmounted:
            mount()
        default:
            //no op the other cases
            break
        }
    }
    var shouldShowOpenIcon: Bool {
        share.connected == .mounted || share.connected == .unmounting
    }
    var shouldDisableMountBoutton: Bool {
        share.connected == .mounting || share.connected == .unmounting
    }

}

struct MountCell: View {
    @Bindable var model: MountCellModel
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
