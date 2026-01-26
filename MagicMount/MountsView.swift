//
//  ContentView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/24/25.
//

import SwiftUI

struct MountsView: View {
    @Environment(MountsViewModel.self) var model
    @State private var showNew : Bool = false
    @AppStorage("showMenuInBar",  store: UserDefaults(suiteName: "group.org.tassinari.magicmount")) private var showMenuBar = true
    
    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            HStack {
                Text("Shares")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack{
                    Toggle("Menu Bar Icon", isOn: $showMenuBar)
                        .toggleStyle(.switch)
                   
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .bottom
            )

            // MARK: - List
            SharesListView(shares: model.mounts)
           

            // MARK: - Bottom Bar
            HStack {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title)
                }
                .buttonStyle(.borderless)

                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title)
                        
                   
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .top
            )
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showNew, content: {
            NewMount()
        })
    }
}

#Preview {
    MountsView()
}
