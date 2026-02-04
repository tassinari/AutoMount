//
//  SharesTableView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//



import SwiftUI
import libMounter

struct SharesListView: View {
    @Environment(ShareDataModel.self) var model
    @State private var selectedShare: Share? = nil

    private var connectedShares: [Share] {
        model.shares.filter { $0.connected == .mounted || $0.connected == .unmounting }
    }

    private var notConnectedShares: [Share] {
        model.shares.filter { $0.connected == .unmounted || $0.connected == .mounting}
    }

    var body: some View {
        List {
            if !connectedShares.isEmpty {
                Section("Connected") {
                    ForEach(connectedShares) { share in
                        MountCell(share: share)
                    }
                }
            }

            if !notConnectedShares.isEmpty {
                Section("Not Connected") {
                    ForEach(notConnectedShares) { share in
                        MountCell(share: share)
                    }
                }
            }
        }
        .listStyle(.inset)
        .sheet(item: $selectedShare) { share in
           // AddEditMount()
            
           
        }
    }

   
}

#Preview {
    SharesListView().environment(MockStore.store)
}
