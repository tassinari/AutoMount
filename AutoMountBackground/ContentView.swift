//
//  ContentView.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI
import libMounter


struct ContentView: View {
    @State var model : ShareDataModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("common.app_name")
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    model.openApp()
                } label: {
                    Text("background.button.settings")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding([.top], 12)
            .padding([.leading, .trailing], 20)
           
            Divider()
                .padding([.leading, .trailing], 20)
                .padding([.top], 12)
            List() {
                if !model.shares.isEmpty {
                    ForEach(model.shares, id:\.self) { share in
                        ContentCellView(share: share) { passedShare, type in
                            switch type{
                                
                            case .open:
                                share.open()
                            case .mount:
                                Task{
                                    do{
                                        switch passedShare.connected{
                                            
                                        case .mounted:
                                            _ = try await  model.unmount(passedShare)
                                        case .unmounted:
                                            _ = try await  model.mount(passedShare)
                                        default:
                                            break
                                        }
                                       
                                    }catch{
                                        MagicMountBackground.error("mount/unmout error \(String(describing: error))")
                                    }
                                }
                               
                            }
                        }
                    }

                }else{
                    Text("background.empty_state")
                }
            }
            .listStyle(.plain)
            .padding([.top, .bottom], 12)
            
        }
        
        
    }
}
enum ButtonActionType{
    case open, mount
}

extension Share{
    var textColor : Color{
        connected == .mounted || connected == .unmounting  ? .primary : .secondary
    }
    var buttonDisabled : Bool{
        connected == .mounting || connected == .unmounting
    }
}


struct ContentCellView: View {
    @State private var hovering = false
    var share: Share
    let actionHandler : (Share, ButtonActionType) -> Void
    
    var body: some View {
        Button {
            actionHandler(share, .open)
        } label: {
            HStack(spacing: 0){
                Text(share.name ?? "--")
                    .foregroundStyle(share.textColor)
                Spacer()
                Button {
                    actionHandler(share, .mount)
                } label: {
                    switch share.connected {
                    case .mounted:
                        Image(systemName: "eject")
                    case .unmounted:
                        Image(systemName: "arrow.up.circle")
                    case .mounting, .unmounting:
                        ProgressView()
                            .controlSize(.mini)
                                .frame(width: 16, height: 16)
                    }

                }
                .buttonStyle(.borderless)
                .disabled(share.buttonDisabled)
            }
            .contentShape(Rectangle())  //allows taps on empty space in cell
        }
        .buttonStyle(.plain)
        .padding([.leading, .trailing],12)
        .padding([.top, .bottom],6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                               .fill(hovering ? Color.gray.opacity(0.15) : .clear)
        )
        .onHover(perform: {
            if share.connected == .mounted{
                self.hovering = $0
            }
            else {self.hovering = false}
        })
        
    }
}


#Preview {
    ContentView(model: MockStore.store)
}
