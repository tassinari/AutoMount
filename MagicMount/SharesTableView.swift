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
        shares.filter { $0.connected }
    }

    private var notConnectedShares: [Share] {
        shares.filter { !$0.connected }
    }

    var body: some View {
        List {
            if !connectedShares.isEmpty {
                Section("Connected") {
                    ForEach(connectedShares) { share in
                        row(for: share)
                    }
                }
            }

            if !notConnectedShares.isEmpty {
                Section("Not Connected") {
                    ForEach(notConnectedShares) { share in
                        row(for: share)
                    }
                }
            }
        }
        .listStyle(.inset)
        .sheet(item: $selectedShare) { share in
            AddManagedView(share: share)
        }
    }

    @ViewBuilder
    private func row(for share: Share) -> some View {
        HStack(spacing: 12) {

            // Status
            if share.managed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            } else {
                Button("Manage") {
                    selectedShare = share
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 80, alignment: .leading)
            }

            // Name
            Text(share.name)
                .fontWeight(.medium)
                .frame(minWidth: 120, alignment: .leading)

            // Mount Point
            Text(share.mountPoint)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 180, alignment: .leading)

            // URL
            Text(share.url.absoluteString)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(minWidth: 200, alignment: .leading)

            // Type
            Text(share.type)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()
        }
        
        .padding(.vertical, 4)
    }
}

#Preview {
    SharesListView(shares: PreviewData.mockShares)
}
