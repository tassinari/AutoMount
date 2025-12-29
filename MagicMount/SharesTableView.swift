//
//  SharesTableView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import SwiftUI



struct SharesTableView: View {

    @State var shares: [Share]
    @State private var selectedShare: Share? = nil

    var body: some View {
        Table(shares) {
            TableColumn("Status") { share in
                if share.managed{
                    Image(systemName:  "checkmark.circle.fill" )
                        .foregroundStyle( .blue)
                }else{
                    Button("Manage") {
                        selectedShare = share
                    }
                    .buttonStyle(.bordered)
                }
               
            }
            .width(80)

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

        }
        .padding()
        .sheet(item: $selectedShare, content: { share in
            AddManagedView(share: share)
               }
        )
       
    }
}

#Preview {
    SharesTableView(shares: PreviewData.mockShares)
}

