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
    @State private var searchText: String = ""
    @Environment(\.openWindow) var openWindow

    private var filteredShares: [Share] {
        guard !searchText.isEmpty else { return model.shares }
        return model.shares.filter { share in
            let term = searchText.lowercased()
            let nameMatch = share.name?.lowercased().contains(term) ?? false
            let urlMatch = share.url.absoluteString.lowercased().contains(term)
            let mountMatch = share.mountPoint?.lowercased().contains(term) ?? false
            return nameMatch || urlMatch || mountMatch
        }
    }

    var body: some View {
        NavigationStack {
            if !model.isLoginItemEnabled {
                Button {
                    openWindow(id: "help")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("MagicMount does not have permission to run in the background. The main functionality of the app will be missing. ")
                        + Text("Click here to learn more.")
                            .bold()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            Table(filteredShares) {
                TableColumn("Managed") { share in
                    ManagedToggleCell(
                        share: share,
                        model: model
                    )
                }
                .width(90)

                TableColumn("Name") { share in
                    HStack {
                        Text(share.name ?? "--")
                        Spacer()
                        MountButtonCell(
                            share: share,
                            model: model
                        )
                    }
                }
                .width(min: 150, ideal: 200)

                TableColumn("Type") { share in
                    Text(share.type.uppercased())
                }
                .width(60)

                TableColumn("Mount Point") { share in
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

                TableColumn("Status") { share in
                    StatusCell(share: share)
                }
                .width(90)
            }
            .tableStyle(.inset)
            .navigationTitle("Network Shares")
            .searchable(text: $searchText, prompt: "Filter shares")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await model.load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
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
