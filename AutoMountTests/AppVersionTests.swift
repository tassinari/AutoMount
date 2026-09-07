//
//  AppVersionTests.swift
//  AutoMountTests
//
//  Created by Claude on 9/7/26.
//

import XCTest
@testable import AutoMount

/// A bundle whose Info dictionary is supplied by the test, so these assertions
/// do not depend on whichever plist the test host was built with.
private final class StubBundle: Bundle, @unchecked Sendable {
    private let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}

final class AppVersionTests: XCTestCase {

    private func version(short: Any? = nil, build: Any? = nil) -> AppVersion {
        var values: [String: Any] = [:]
        if let short { values["CFBundleShortVersionString"] = short }
        if let build { values["CFBundleVersion"] = build }
        return AppVersion(bundle: StubBundle(values: values))
    }

    // MARK: - Reading the plist

    func testReadsVersionAndBuildFromBundle() {
        let subject = version(short: "1.0.3", build: "150")
        XCTAssertEqual(subject.short, "1.0.3")
        XCTAssertEqual(subject.build, "150")
    }

    func testDisplayTextContainsVersionAndBuild() {
        let text = version(short: "1.0.3", build: "150").displayText
        XCTAssertTrue(text.contains("1.0.3"), "expected the marketing version, got: \(text)")
        XCTAssertTrue(text.contains("150"), "expected the build number, got: \(text)")
    }

    /// The bug this guards: the release ships a real version but the build
    /// number is left at the shallow-clone default, and nobody notices.
    func testDisplayTextDistinguishesTwoBuildsOfTheSameVersion() {
        XCTAssertNotEqual(version(short: "1.0.3", build: "150").displayText,
                          version(short: "1.0.3", build: "151").displayText)
    }

    // MARK: - Missing or malformed values

    func testMissingKeysFallBackToUnknown() {
        let subject = version()
        XCTAssertEqual(subject.short, AppVersion.unknown)
        XCTAssertEqual(subject.build, AppVersion.unknown)
    }

    func testEmptyStringFallsBackToUnknown() {
        XCTAssertEqual(version(short: "", build: "").short, AppVersion.unknown)
    }

    func testWhitespaceOnlyValueFallsBackToUnknown() {
        XCTAssertEqual(version(short: "   ", build: "   ").build, AppVersion.unknown)
    }

    /// A plist value that is not a string (a number, say) must not crash the
    /// About box; it degrades to the unknown marker like any other bad value.
    func testNonStringValueFallsBackToUnknown() {
        XCTAssertEqual(version(short: 103, build: 150).short, AppVersion.unknown)
    }

    func testFallbackIsNeverEmpty() {
        XCTAssertFalse(AppVersion.unknown.isEmpty,
                       "a blank version reads as a layout bug rather than missing data")
    }

    func testPartialInfoDictionaryKeepsTheValueItHas() {
        let subject = version(short: "2.1.0")
        XCTAssertEqual(subject.short, "2.1.0")
        XCTAssertEqual(subject.build, AppVersion.unknown)
    }

    // MARK: - The real bundle

    /// The shipping app must not display the unknown marker: Xcode always
    /// generates both keys, so hitting the fallback means the Info.plist
    /// generation changed underneath us.
    func testMainBundleSuppliesBothKeys() {
        let subject = AppVersion(bundle: .main)
        XCTAssertNotEqual(subject.short, AppVersion.unknown)
        XCTAssertNotEqual(subject.build, AppVersion.unknown)
    }
}
