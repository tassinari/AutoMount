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
        for share in shares {
            share.connected = connected.contains(share)
            print("\(share.name) -> \(share.connected)")
        }
    }
    func open(share: Share){
        let url = URL(filePath: share.mountPoint)
        if FileManager.default.fileExists(atPath: url.path){
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        
    }
    func openApp(){
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.tassinari.PhotoVaultManager"){
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
    func toggleMount(share: Share){
        Task{
            do{
                if share.connected {
                    try await MountData.unmount(url: URL(filePath: share.mountPoint))
                }else{
                    switch try await share.mountData?.mount(){
                        
                    case .success(_):
                        print("mount")
                        break;
                    default:
                        print("no success")
                        break
                    }
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
                                model.open(share: share)
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
                    .foregroundStyle(share.connected ? .black : .gray.opacity(0.5))
                Spacer()
                Button {
                    actionHandler(share, .mount)
                } label: {
                    share.connected ? Image(systemName: "eject") : Image(systemName: "arrow.up.circle")
                }
                .buttonStyle(.borderless)
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
        .onHover(perform: {self.hovering = $0})
        
    }
}


#Preview {
    ContentView(model: MenuModel())
}
