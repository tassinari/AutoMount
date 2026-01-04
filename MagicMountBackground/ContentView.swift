//
//  ContentView.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI

struct MountViewModel{
    var mounts : [Share]
    
    func refresh(){
        
    }
}

struct ContentView: View {
    @State var connectedShares : [Share] = StorageManager().fullMountList?.filter({$0.connected}) ?? []
    @State var notConnectedShares : [Share] = StorageManager().fullMountList?.filter({!$0.connected}) ?? []
    var body: some View {
        VStack {
            HStack{
                Text("Magic Mount")
                    .font(.caption)
                Spacer()
                Button {
                
                } label: {
                    Text("Open App")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            List {
                if !connectedShares.isEmpty {
                    Section("Connected") {
                        ForEach(connectedShares) { share in
                            HStack{
                                Text(share.name)
                                Spacer()
                                Button {
                                
                                } label: {
                                    Image(systemName: "eject")
                                }
                                .buttonStyle(.plain)

                            }
                        }
                    }
                }

                if !notConnectedShares.isEmpty {
                    Section("Not Connected") {
                        ForEach(notConnectedShares) { share in
                            HStack{
                                Text(share.name)
                                Spacer()
                                Button {
                                
                                } label: {
                                    Image(systemName: "arrow.up.circle")
                                }
                                .buttonStyle(.plain)

                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
