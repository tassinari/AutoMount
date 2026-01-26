//
//  MagicMountApp.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/24/25.
//

import SwiftUI


@main
struct MagicMountApp: App {
    private var model: MountsViewModel = MountsViewModel( service: DefaultServiceInterface())
    var body: some Scene {
        WindowGroup {
            MountsView()
                .environment(model)
        }
        
    }
}
