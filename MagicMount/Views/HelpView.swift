//
//  HelpView.swift
//  MagicMount
//
//

import SwiftUI

struct HelpView: View {
    var anchor: String? = nil
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "help", withExtension: "html") {
                HTMLView(url: url, anchor: anchor)
            } else {
                Text("Help content is unavailable.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
