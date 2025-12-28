//
//  SharesTableView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import SwiftUI



struct SharesTableView: View {

    @State var shares: [Volume]

    var body: some View {
        Table(shares) {

            TableColumn("Name") { share in
                Text(share.name)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Mount Point") { share in
                Text(share.mountPoint)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 180, ideal: 240)

            TableColumn("URL") { share in
                Text(share.url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 200, ideal: 280)

            TableColumn("Type") { share in
                Text(share.type)
            }
            .width(60)

            TableColumn("Local") { share in
                Image(systemName: share.local ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(share.local ? .green : .secondary)
            }
            .width(60)

            TableColumn("Managed") { share in
                Image(systemName: share.isManaged ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(share.isManaged ? .blue : .secondary)
            }
            .width(80)
        }
        .padding()
    }
}

#Preview {
    SharesTableView(shares: PreviewData.mockShares)
}

