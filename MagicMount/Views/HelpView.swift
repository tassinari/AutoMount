//
//  HelpView.swift
//  MagicMount
//
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "help", withExtension: "html") {
                HTMLView(url: url)
            } else {
                Text("Help content is unavailable.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
