//
//  NetworkChangeFilterTests.swift
//  AutoMountBackgroundTests
//
//  Pins that only path updates that could change share reachability start a
//  remount pass. On 2026-10-20 weak Wi-Fi produced an update every 12-20 seconds
//  for ten hours while the connection never dropped.
//

import XCTest
@testable import AutoMountBackground

final class NetworkChangeFilterTests: XCTestCase {

    private let wifi = NetworkSnapshot(isUsable: true, interfaces: ["en0"], gateways: ["192.168.1.1:0"])

    func testFirstUsablePathIsReported() {
        var filter = NetworkChangeFilter()
        XCTAssertTrue(filter.shouldReport(wifi))
    }

    func testRepeatedIdenticalPathIsIgnored() {
        var filter = NetworkChangeFilter()
        _ = filter.shouldReport(wifi)

        for _ in 0..<100 {
            XCTAssertFalse(filter.shouldReport(wifi))
        }
    }

    func testUnusablePathIsNeverReported() {
        var filter = NetworkChangeFilter()
        let down = NetworkSnapshot(isUsable: false, interfaces: [], gateways: [])

        XCTAssertFalse(filter.shouldReport(down))
        XCTAssertFalse(filter.shouldReport(down))
    }

    func testReturningAfterOutageIsReported() {
        var filter = NetworkChangeFilter()
        _ = filter.shouldReport(wifi)

        XCTAssertFalse(filter.shouldReport(NetworkSnapshot(isUsable: false, interfaces: [], gateways: [])))
        XCTAssertTrue(filter.shouldReport(wifi))
    }

    /// A path can lose DNS without losing its interface; getting DNS back counts.
    func testRegainingDNSOnSameInterfaceIsReported() {
        var filter = NetworkChangeFilter()
        _ = filter.shouldReport(wifi)

        let noDNS = NetworkSnapshot(isUsable: false, interfaces: ["en0"], gateways: ["192.168.1.1:0"])
        XCTAssertFalse(filter.shouldReport(noDNS))
        XCTAssertTrue(filter.shouldReport(wifi))
    }

    func testSwitchingInterfaceIsReported() {
        var filter = NetworkChangeFilter()
        _ = filter.shouldReport(wifi)

        let ethernet = NetworkSnapshot(isUsable: true, interfaces: ["en7"], gateways: ["192.168.1.1:0"])
        XCTAssertTrue(filter.shouldReport(ethernet))
    }

    func testVPNComingUpIsReported() {
        var filter = NetworkChangeFilter()
        _ = filter.shouldReport(wifi)

        let vpn = NetworkSnapshot(isUsable: true, interfaces: ["utun4", "en0"], gateways: ["192.168.1.1:0"])
        XCTAssertTrue(filter.shouldReport(vpn))
        XCTAssertFalse(filter.shouldReport(vpn))
        XCTAssertTrue(filter.shouldReport(wifi), "VPN going down changes the path back")
    }

    func testUniquedDropsRepeatsAndKeepsOrder() {
        XCTAssertEqual(NetworkSnapshot.uniqued(["en0", "en0", "utun3", "en0"]), ["en0", "utun3"])
        XCTAssertEqual(NetworkSnapshot.uniqued([]), [])
    }

    func testJoiningAnotherNetworkOnSameInterfaceIsReported() {
        var filter = NetworkChangeFilter()
        _ = filter.shouldReport(wifi)

        let office = NetworkSnapshot(isUsable: true, interfaces: ["en0"], gateways: ["10.0.0.1:0"])
        XCTAssertTrue(filter.shouldReport(office))
    }

    /// With Ethernet and Wi-Fi both up, a change in the preferred one reorders the list.
    /// Order matters, so this must stay a change (don't compare as a `Set`).
    func testSwappingInterfaceOrderIsReported() {
        var filter = NetworkChangeFilter()
        let both = NetworkSnapshot(isUsable: true, interfaces: ["en0", "en7"], gateways: ["192.168.1.1:0"])
        _ = filter.shouldReport(both)

        let swapped = NetworkSnapshot(isUsable: true, interfaces: ["en7", "en0"], gateways: ["192.168.1.1:0"])
        XCTAssertTrue(filter.shouldReport(swapped))
    }

    func testTrackerCountsIgnoredUpdatesAndResetsOnReport() {
        var tracker = NetworkChangeTracker()
        XCTAssertEqual(tracker.report(wifi), 0)

        for _ in 0..<3 {
            XCTAssertNil(tracker.report(wifi))
        }
        let ethernet = NetworkSnapshot(isUsable: true, interfaces: ["en7"], gateways: ["192.168.1.1:0"])
        XCTAssertEqual(tracker.report(ethernet), 3)
        XCTAssertNil(tracker.report(ethernet))
        XCTAssertEqual(tracker.report(wifi), 1)
    }

    func testTrackerCountsUnusablePathsAsIgnored() {
        var tracker = NetworkChangeTracker()
        _ = tracker.report(wifi)

        XCTAssertNil(tracker.report(NetworkSnapshot(isUsable: false, interfaces: [], gateways: [])))
        XCTAssertEqual(tracker.report(wifi), 1)
    }
}
