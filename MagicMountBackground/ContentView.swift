//
//  ContentView.swift
//  MagicMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI
import libMounter
//struct MountViewModel{
//    var mounts : [Share]
//    
//    func refresh(){
//        
//    }
//}
@Observable class MenuModel{
    
    var shares : [Share]
    let storage : Storage
    
    init(storage : Storage = StorageManager()){
        self.storage = storage
        shares = []
        Task{
            shares = await storage.fullMountList()
        }
        
    }
    func refresh(){
        Task{
            //current state
            let updated = await storage.fullMountList()
            //find new shares
            let added = Set(updated).subtracting(shares)
            //find missing shares, shares that were switched to unmanaged and unmounted
            let missing = Set(shares).subtracting(updated)
            //make and updated list with same instances
            var fullUpdated : [Share] = []
//            for share in shares{
//                if missing.contains(share){
//                    continue;
//                }
//                if let sameShareFromUpdated = updated.first(where: {$0 == share}){
//    //                share.connected = sameShareFromUpdated.connected
//    //                share.managed = sameShareFromUpdated.managed
//                }
//                fullUpdated.append(share)
//            }
            fullUpdated.append(contentsOf: added)
            shares = fullUpdated
        }
        
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
                    try await storage.unmount(share)
                case .unmounted:
                    switch try await storage.mount(share, ui: false){
                        
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
    ContentView(model: MenuModel())
}
