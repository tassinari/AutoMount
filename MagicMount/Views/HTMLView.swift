//
//  HTMLView.swift
//  MagicMount
//
//

import SwiftUI
import WebKit

struct HTMLView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
