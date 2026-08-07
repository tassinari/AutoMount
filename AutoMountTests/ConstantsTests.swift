//
//  ConstantsTests.swift
//  AutoMountTests
//
//  Created by Claude on 2/22/26.
//

import XCTest
@testable import AutoMount

final class ConstantsTests: XCTestCase {

    func testNetworkDebounceDefaultIsInOptions() {
        XCTAssertTrue(Constant.networkDebounceOptions.contains(Constant.networkDebounceDefault))
    }

    func testPeriodicRemountDefaultIsInOptions() {
        XCTAssertTrue(Constant.periodicRemountOptions.contains(Constant.periodicRemountDefault))
    }

    func testNetworkDebounceOptionsAreAscending() {
        XCTAssertEqual(Constant.networkDebounceOptions, Constant.networkDebounceOptions.sorted())
    }

    func testPeriodicRemountOptionsAreAscending() {
        XCTAssertEqual(Constant.periodicRemountOptions, Constant.periodicRemountOptions.sorted())
    }
}
