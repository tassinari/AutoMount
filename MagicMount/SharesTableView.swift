//
//  SharesTableView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//



import SwiftUI

struct SharesListView: View {

    let shares: [Share]
    @State private var selectedShare: Share? = nil

    private var connectedShares: [Share] {
        shares.filter { $0.connected == .mounted || $0.connected == .unmounting }
    }

    private var notConnectedShares: [Share] {
        shares.filter { $0.connected == .unmounted || $0.connected == .mounting}
    }

    var body: some View {
        List {
            if !connectedShares.isEmpty {
                Section("Connected") {
                    ForEach(connectedShares) { share in
                        MountCell(model: MountCellModel(share: share, handler: { passedShare in
                            self.selectedShare = passedShare
                        }))
                    }
                }
            }

            if !notConnectedShares.isEmpty {
                Section("Not Connected") {
                    ForEach(notConnectedShares) { share in
                        MountCell(model: MountCellModel(share: share, handler: { passedShare in
                            self.selectedShare = passedShare
                        }))
                    }
                }
            }
        }
        .listStyle(.inset)
        .sheet(item: $selectedShare) { share in
            AddManagedView(share: share)
        }
    }

   
}

#Preview {
    SharesListView(shares: PreviewData.mockShares)
}
