//
//  ContentView.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI

//struct MountViewModel{
//    var mounts : [Share]
//    
//    func refresh(){
//        
//    }
//}
@Observable class MenuModel{
    
    var shares : [Share]
    
    init(){
        shares = StorageManager().fullMountList ?? []
        refresh()
    }
    func refresh(){
        let connected = MountInfo.mountedVolumes().filter({$0.type != "file"})
        
        //update status of shares we know about
        for share in shares {
            share.connected = connected.contains(share) ? .mounted : .unmounted
            print("\(share.name) -> \(share.connected)")
        }
        //append any new shares
        let newShares = Set(connected).subtracting(shares)
        shares.append(contentsOf: newShares)
    }
    func openApp(){
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.tassinari.MagicMount"){
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
    func toggleMount(share: Share){
        Task{
            do{
                switch share.connected{
                case .mounted:
                    try await share.unmount()
                case .unmounted:
                    switch try await share.mount(){
                        
                    case .success(_):
                        print("mount")
                        break;
                    default:
                        print("no success")
                        break
                    }
                case .mounting, .unmounting:
                    //no op
                    break
                }
            }catch{
                MagicMountBackground.error(String(describing: error))
            }
        }
    }
}

struct ContentView: View {
    @State var model : MenuModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Magic Mount")
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    model.openApp()
                } label: {
                    Text("Settings")
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
                    ForEach(model.shares) { share in
                        ContentCellView(share: share) { passedShare, type in
                            switch type{
                                
                            case .open:
                                share.open()
                            case .mount:
                                model.toggleMount(share: share)
                            }
                        }
                    }

                }else{
                    Text("No shares")
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
        connected == .mounted || connected == .unmounting  ? .black : .gray.opacity(0.5)
    }
    var buttonDisabled : Bool{
        connected == .mounting || connected == .unmounting
    }
}


struct ContentCellView: View {
    @State private var hovering = false
    @Bindable var share: Share
    let actionHandler : (Share, ButtonActionType) -> Void
    
    var body: some View {
        Button {
            actionHandler(share, .open)
        } label: {
            HStack(spacing: 0){
                Text(share.name)
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
    ContentView(model: MenuModel())
}
