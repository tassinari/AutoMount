//
//  ShareDataModelBlockingTests.swift
//  AutoMountTests
//
//  `ShareDataModel` is `@MainActor`, and `load()` runs on every volume mount/unmount
//  notification. It must await storage rather than doing filesystem work inline, or a
//  slow/unreachable server freezes the UI.
//

import XCTest
import libMounter
import ServiceManagement
@testable import AutoMount

final class ShareDataModelBlockingTests: XCTestCase {

    private func makeShare(name: String, connected: ConnectionState = .unmounted) -> Share {
        Share(url: URL(string: "smb://server/\(name)")!,
              name: name,
              mountPoint: "/Volumes/\(name)",
              managed: true,
              connected: connected)
    }

    /// A slow `fullMountList` must not block the main actor while it is in flight.
    @MainActor func testSlowLoadDoesNotBlockMainActor() async throws {
        let storage = SlowMockStorage(delay: .milliseconds(600), list: [makeShare(name: "media")])
        let model = ShareDataModel(storage: storage, appService: MockSMService(mockStatus: .enabled))

        let loadTask = Task { await model.load() }

        // The main actor must remain free to run work while the load is outstanding.
        try await Task.sleep(for: .milliseconds(100))
        let start = Date()
        var counter = 0
        for _ in 0..<1000 { counter += 1 }
        let latency = Date().timeIntervalSince(start)

        XCTAssertEqual(counter, 1000)
        XCTAssertLessThan(latency, 0.3, "Main actor blocked for \(latency)s during load()")
        await loadTask.value
        XCTAssertEqual(model.shares.count, 1)
    }

    /// Mounting swaps in a `.mounting` placeholder before awaiting storage, so the UI shows
    /// progress immediately rather than sitting frozen until the mount returns.
    @MainActor func testMountShowsProgressStateWhileMountIsInFlight() async throws {
        let share = makeShare(name: "media")
        let storage = SlowMockStorage(delay: .milliseconds(400), list: [share])
        let model = ShareDataModel(storage: storage, appService: MockSMService(mockStatus: .enabled))
        await model.load()

        let mountTask = Task { try await model.mount(share) }
        // Let the placeholder swap happen, but finish well before the mount completes.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.shares.first?.connected, .mounting,
                       "The row should show a mounting state while the mount is in flight")
        _ = try await mountTask.value
    }

    @MainActor func testUnmountShowsProgressStateWhileUnmountIsInFlight() async throws {
        let share = makeShare(name: "media", connected: .mounted)
        let storage = SlowMockStorage(delay: .milliseconds(400), list: [share])
        let model = ShareDataModel(storage: storage, appService: MockSMService(mockStatus: .enabled))
        await model.load()

        let unmountTask = Task { try await model.unmount(share) }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.shares.first?.connected, .unmounting,
                       "The row should show an unmounting state while the unmount is in flight")
        try await unmountTask.value
    }
}

/// A `Storage` whose operations take a controllable amount of time, standing in for an
/// unresponsive server.
private final class SlowMockStorage: Storage, @unchecked Sendable {
    private let delay: Duration
    private let list: [Share]

    init(delay: Duration, list: [Share]) {
        self.delay = delay
        self.list = list
    }

    func fullMountList() async -> [Share] {
        try? await Task.sleep(for: delay)
        return list
    }

    func addMount(_ mount: Share) async throws {}
    func deleteMount(_ mount: Share) async throws {}

    func mount(_ share: Share, ui: Bool) async throws -> MountResponse {
        try? await Task.sleep(for: delay)
        return .success(share.mountPoint)
    }

    func unmount(_ share: Share) async throws {
        try? await Task.sleep(for: delay)
    }
}
