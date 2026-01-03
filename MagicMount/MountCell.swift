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
    var working : Bool = false
    
    init(share: Share, handler: ((Share) -> Void)? = nil){
        self.share = share
        self.manageHandler = handler
    }
    
    func eject(){
        working = true
        Task{
            defer{
                working = false
            }
            do{
                try await share.unmount()
            }
            catch{
                //FIXME: logger
            }
        }
    }
    func mount(){
        working = true
        Task{
            defer{
                working = false
            }
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
}

struct MountCell: View {
    var model: MountCellModel
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack(alignment: .center){
                       if model.share.connected{
                           Image(systemName: "externaldrive.badge.checkmark")
                               .font(.title2)
                               .foregroundStyle(.green)
                       }else{
                           Image(systemName: "externaldrive.badge.xmark")
                               .font(.title2)
                               .foregroundStyle(.gray)
                       }
                        Text(model.share.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text(model.share.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                if model.share.connected{
                    HStack {
                        Text(model.share.mountPoint)
                            .font(.title2)
                        Button {
                            
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
                if !model.working{
                    Button {
                        //FIXME: debounce this
                        model.share.connected ?  model.eject() : model.mount()
                        
                    } label: {
                        if model.share.connected{
                            Image(systemName: "eject")
                                .foregroundStyle(.gray)
                                .font(.title2)
                        }else{
                            Text("Mount")
                            
                        }
                        
                    }
                    .buttonStyle(.glass)
                    .disabled(model.working)
                }else{
                    ProgressView()
                }
                
               
            }
            
        }
        .padding()
    }
}

#Preview {
    MountCell(model: MountCellModel(share: Share(user: "", password: "", url: URL(string: "smb://127.0.0.1/photos")!, name: "Photos", mountPoint: "/Volumes/photos", managed: true, connected: true)))
        .frame(width: 400, height: 150)
}
