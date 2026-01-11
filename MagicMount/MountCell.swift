//
//  MountCell.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/1/26.
//

import SwiftUI

@Observable class MountCellModel {
    let share: Share
    let manageHandler : ((Share) -> Void)?
    
    init(share: Share, handler: ((Share) -> Void)? = nil){
        self.share = share
        self.manageHandler = handler
    }
    
    func eject(){
        Task{
            do{
                try await share.unmount()
            }
            catch{
                //FIXME: logger
            }
        }
    }
    func mount(){
        
        Task{
            do{
                switch try await share.mount(){
                case .success(_):
                    break
                default:
                    //FIXME: logger
                    print("error")
                }
            }catch {
                //FIXME: logger

            }
        }
        
    }
    func edit(){
        manageHandler?(share)
    }
    func mountUnmountPressed(){
        switch share.connected{
        case .mounted:
            eject()
        case .unmounted:
            mount()
        default:
            //no op the other cases
            break
        }
    }
    var shouldShowOpenIcon : Bool{
        share.connected == .mounted || share.connected == .unmounting
    }
    var shouldDisableMountBoutton : Bool{
        share.connected == .mounting || share.connected == .unmounting
    }
    
}


struct MountCell: View {
    var model: MountCellModel
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack(alignment: .center){
                        driveIcon
                        Text(model.share.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text(model.share.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                if model.shouldShowOpenIcon{
                    HStack {
                        Text(model.share.mountPoint)
                            .font(.title2)
                        Button {
                            model.share.open()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)

                    }
                }
                
            }
           
            
           Spacer()
            HStack {
                Spacer()
                Button {
                    model.edit()
                } label: {
                    Text(model.share.managed ? "Edit" : "Manage")
                }
                .buttonStyle(.glass)
                
                Button {
                    model.mountUnmountPressed()
                } label: {
                    mountButtonLabel
                }
                .buttonStyle(.glass)
                .disabled(model.shouldDisableMountBoutton)
                
                
               
            }
            
        }
        .padding()
    }
    var driveIcon: some View{
        switch model.share.connected{
        case .mounted, .unmounting:
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.green)
        case .unmounted, .mounting:
            Image(systemName: "externaldrive.badge.xmark")
                .font(.title2)
                .foregroundStyle(.gray)
        }
    }
    @ViewBuilder var mountButtonLabel: some View{
        switch model.share.connected{
        case .mounted, .unmounting:
            Image(systemName: "eject")
                .foregroundStyle(.gray)
                .font(.title2)
        case .unmounted, .mounting:
            Text("Mount")
            
        }
    }
}

#Preview {
    MountCell(model: MountCellModel(share: Share(user: "", password: "", url: URL(string: "smb://127.0.0.1/photos")!, name: "Photos", mountPoint: "/Volumes/photos", managed: true, connected: true)))
        .frame(width: 400, height: 150)
}
