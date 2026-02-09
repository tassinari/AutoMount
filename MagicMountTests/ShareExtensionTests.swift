//
//  ShareExtensionTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 2/4/26.
//

import XCTest
import Foundation
import libMounter
@testable import MagicMount

final class ShareExtensionTests: XCTestCase {
    
    func testShareIconTextMounted() {
        let share = Share( url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounted)
        XCTAssertEqual(share.iconText, Constant.shareIconTextMounted)
    }
    func testShareIconTextUnMounted() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        XCTAssertEqual(share.iconText, Constant.shareIconTextUnMounted)
    }
    func testShareIconTextMounting() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounting)
        XCTAssertEqual(share.iconText, Constant.shareIconTextMounting)
    }
    func testShareIconTextUnMounting() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounting)
        XCTAssertEqual(share.iconText, Constant.shareIconTextUnMounting)
    }
    func testShareICanOpenMounted() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounted)
        XCTAssertTrue(share.canOpen)
    }
    func testShareICanOpenUnMounted() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        XCTAssertFalse(share.canOpen)
    }
    func testShareICanOpenMounting() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounting)
        XCTAssertFalse(share.canOpen)
    }
    func testShareICanOpenUnmounting() {
        let share = Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounting)
        XCTAssertFalse(share.canOpen)
    }
}
