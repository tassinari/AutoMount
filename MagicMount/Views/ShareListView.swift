//
//  ShareListView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/3/26.
//



import SwiftUI
import AppKit
import libMounter
// MARK: - Main View

struct ShareListView: View {
    @State var model: ShareDataModel
    @State private var errorMessage: String?

    var body: some View {
        //@Bindable var bindableModel = model
        VStack(spacing: 0) {
            header

            Table($model.shares){
                TableColumn("Managed") { $share in
                    ManagedToggleCell(
                        share: $share,
                        model: model
                    )

                }

                .width(90)
                TableColumn("Name") { $share in
                    HStack{
                        Text(share.name ?? "--")
                        Spacer()
                        MountButtonCell(
                            share: $share,
                            model: model
                        )
                    }
                }
                .width(min: 150, ideal: 200)

                TableColumn("Type") { $share in
                    Text(share.type.uppercased())
                }
                .width(60)

                TableColumn("Mount Point") { $share in
                    if share.canOpen {
                        Button {
                            share.open()
                        } label: {
                            Text(share.mountPoint ?? "--")
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)

                    }else{
                        Text(share.mountPoint ?? "")
                            .lineLimit(1)
                    }
                   
                }

                

                TableColumn("Status") { $share in
                    StatusCell(share: share)
                }
                .width(90)

                
            }
            .tableStyle(.inset)
        }
        .frame(minWidth: 750, minHeight: 400)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $model.showAddShare, content: {
            AddEditMount(model: AddEditModel(store: model))
        })
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Network Shares")
                .font(.title2.bold())

            Spacer()

            Button {
                Task { await model.load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Managed Toggle Cell

struct ManagedToggleCell: View {

    @Binding var share: Share
    let model: ShareDataModel

    @State private var isWorking = false

    var body: some View {
        Toggle("", isOn: managedBinding)
            .labelsHidden()
        .disabled(isWorking)
    }
    private var managedBinding: Binding<Bool> {
           Binding(
               get: { share.managed },
               set: { newValue in
                   updateManaged(newValue)
               }
           )
       }

       private func updateManaged(_ value: Bool) {
           isWorking = true

           Task {
               do {
                   if value {
                       try await model.manage(share)
                   } else {
                       try await model.unmanage(share)
                   }
               } catch {
                   NSLog("Manage error: \(error)")
               }

               await MainActor.run {
                   isWorking = false
               }
           }
       }

}

// MARK: - Status Cell

struct StatusCell: View {

    let share: Share

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.system(size: 12))
        }
    }

    private var statusText: String {
        switch share.connected {
        case .mounted:
            return "Mounted"
        case .unmounted:
            return "Unmounted"
        case .mounting:
            return "Connecting"
        case .unmounting:
            return "Ejecting"
        }
    }

    private var statusColor: Color {
        switch share.connected {
        case .mounted:
            return .green
        case .unmounted:
            return .secondary
        case .mounting:
            return .orange
        case .unmounting:
            return .orange
        }
    }
}

// MARK: - Mount / Unmount Button Cell

struct MountButtonCell: View {

    @Binding var share: Share
    let model: ShareDataModel

    @State private var isWorking = false

    var body: some View {
        if share.showProgressView {
            ProgressView()
                .controlSize(.small)
        }else{
            Button {
                handleAction()
            } label: {
                Image(systemName:  share.iconText)
                    .font(.body)
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }



    private func handleAction() {
        isWorking = true

        Task {
            do {
                switch share.connected {
                case .mounted:
                    try await model.unmount(share)

                case .unmounted:
                    _ = try await model.mount(share)

                default:
                    break
                }
            } catch {
                NSLog("Mount error: \(error)")
            }

            await MainActor.run {
                isWorking = false
            }
        }
    }
}

// MARK: - Preview (Mock)

#if DEBUG

struct ShareListView_Previews: PreviewProvider {

    static var previews: some View {
        ShareListView(model: MockStore.store)
    }
}

#endif
