//
//  MountsViewModel.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/25/26.
//
import Foundation
import libMounter
import AppKit
import ServiceManagement
import SwiftUI

@Observable final class MountsViewModel{
   
    @MainActor init( service : AppServiceInterface) {
        
        do{
            switch service.status {
            case .notRegistered:
                try service.register()
            case .enabled:
                MagicMount.notice("SMService enabled")
                break // No-op, already approved
            case .requiresApproval:
                //TODO: show note in UI on how to enable
                MagicMount.notice("SMService requires approval")
                break
            case .notFound:
                MagicMount.notice("SMService not found!")
            @unknown default:
                break
            }
        }catch{
            MagicMount.error("SMService start threw error: \(String(describing: error))")
        }
        refresh()
        
    }
   
    func refresh(){
        
    }
    


}
