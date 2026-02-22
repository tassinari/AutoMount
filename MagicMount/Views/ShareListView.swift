//
//  ShareListView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/3/26.
//

//FIXME: Remove Files DVDs and DMGs


import SwiftUI
import AppKit
import libMounter
// MARK: - Main View

struct ShareListView: View {
    @State var model: ShareDataModel
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var sortOrder: [KeyPathComparator<Share>] = [
        KeyPathComparator(\.sortableName, order: .forward)
    ]
    @Environment(\.openWindow) var openWindow

    private var filteredShares: [Share] {
        let base: [Share]
        if searchText.isEmpty {
            base = model.shares
        } else {
            let term = searchText.lowercased()
            base = model.shares.filter { share in
                let nameMatch = share.name?.lowercased().contains(term) ?? false
                let urlMatch = share.url.absoluteString.lowercased().contains(term)
                let mountMatch = share.mountPoint?.lowercased().contains(term) ?? false
                return nameMatch || urlMatch || mountMatch
            }
        }
        return base.sorted(using: sortOrder)
    }

    var body: some View {
        NavigationStack {
            if !model.isLoginItemEnabled {
                HStack(alignment: .top){
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding([.top], 4)
                    VStack(alignment: .leading){
                        HStack(spacing: 2) {
                            Text("MagicMount does not have permission to run in the background. The main functionality of the app will be missing.")
                                .font(.headline)
                                .fontWeight(.light)
                            Button {
                                openWindow(id: "help-background")
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        if model.canOpenURL {
                            Button {
                                model.openSettings()
                            } label: {
                                Text("Open System Settings to enable")
                            }
                            .buttonStyle(.link)
                        }else{
                            Text(model.aleternatOpenString)
                                .font(.callout)
                                .padding(4)
                            
                        }

                    }
                        
                        
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15))
               
            }
            Table(filteredShares, sortOrder: $sortOrder) {
                TableColumn("Auto Mount", sortUsing: KeyPathComparator(\.sortableManaged)) { share in
                    ManagedToggleCell(
                        share: share,
                        model: model
                    )
                }
                .width(90)

                TableColumn("Name", sortUsing: KeyPathComparator(\.sortableName)) { share in
                    HStack {
                        Text(share.name ?? "--")
                        Spacer()
                        MountButtonCell(
                            share: share,
                            model: model,
                            errorMessage: $errorMessage
                        )
                    }
                }
                .width(min: 150, ideal: 200)

                TableColumn("Type", sortUsing: KeyPathComparator(\.type)) { share in
                    Text(share.type.uppercased())
                }
                .width(60)

                TableColumn("Mount Point", sortUsing: KeyPathComparator(\.sortableMountPoint)) { share in
                    if share.canOpen {
                        Button {
                            share.open()
                        } label: {
                            Text(share.mountPoint ?? "--")
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)
                    } else {
                        Text(share.mountPoint ?? "")
                            .lineLimit(1)
                    }
                }

                TableColumn("Status", sortUsing: KeyPathComparator(\.sortableStatus)) { share in
                    StatusCell(share: share)
                }
                .width(90)
            }
            .tableStyle(.inset)
            .searchable(text: $searchText)
            .toolbar {
               
                ToolbarItem {
                    Button {
                        model.showAddShare = true
                    } label: {
                        Label("Add Share", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 750, minHeight: 400)
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $model.showAddShare, content: {
            AddEditMount(model: AddEditModel(store: model), errorMessage: $errorMessage)
        })
    }
}

// MARK: - Managed Toggle Cell

struct ManagedToggleCell: View {

    let share: Share
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

    let share: Share
    let model: ShareDataModel
    
    @Binding var errorMessage:  String?
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
                    let resp = try await model.mount(share)
                    switch resp{
                    case .success:
                        break
                    default:
                        let err = AddEditModelError.mountFailed(resp)
                        errorMessage = err.localizedDescription
                    }

                default:
                    break
                }
            } catch {
                errorMessage = error.localizedDescription
                MagicMount.error("Mount button pressed error: \(String(describing: error))")
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
