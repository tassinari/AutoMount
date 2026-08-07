//
//  HTMLView.swift
//  MagicMount
//
//

import SwiftUI
import WebKit

struct HTMLView: NSViewRepresentable {
    let url: URL
    var anchor: String? = nil

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        var loadURL = url
        if let anchor, let urlWithAnchor = URL(string: url.absoluteString + "#\(anchor)") {
            loadURL = urlWithAnchor
        }
        webView.loadFileURL(loadURL, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
