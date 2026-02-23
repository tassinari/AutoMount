//
//  NewMountModelTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 12/27/25.
//

import XCTest
import Foundation
import libMounter
@testable import MagicMount




final class AddEditModelTests: XCTestCase {
    var store : ShareDataModel!
    
    @MainActor override func setUpWithError() throws {
        store = ShareDataModel(storage: MockStorage())
    }
   
    
    @MainActor func testInitEmpty() async throws{
        let model = AddEditModel(store: store)
        XCTAssertEqual(model.urlString, "")
      
    }
    @MainActor func testInitHoldsAllValues() async throws{
        let url = "urlString"
       
        let model = AddEditModel(urlString: url, store: store)
        XCTAssertEqual(model.urlString, url)
       
    }
    @MainActor func testClearWorks() async throws{
        let url = "urlString"
         let model = AddEditModel(urlString: url,  store: store)
        model.manage = false
        XCTAssertEqual(model.urlString, url)
    
        model.clear()
        XCTAssertEqual(model.urlString, "")
        XCTAssertTrue(model.manage)
   
        
    }
    @MainActor func testSaveAllCallsMount() async throws{
        let mockStore = MockStorage(mountResponse: .success("/some/path"))
        store = ShareDataModel(storage: mockStore)
        let urlStr = "smb://localhost:445/test"
        let model = AddEditModel(urlString: urlStr, store: store)
        XCTAssertFalse(mockStore.mountCalled)
        try await model.saveAll()
        XCTAssertTrue(mockStore.mountCalled)
    }
    @MainActor func testSaveAllDoesntCallAddMountWhenFlagFalse() async throws{
        let share = Share(url: URL(string: "smb://localhost:445/test")!, name: "test", mountPoint: nil, managed: false, connected: .unmounted)
        let mockStore = MockStorage(list:[share],mountResponse: .success("/some/path"), addHandler:{ _ in
            XCTFail()
        })
        store = ShareDataModel(storage: mockStore)
        let urlStr = "smb://localhost:445/test"
        let model = AddEditModel(urlString: urlStr, store: store)
        model.manage = false
        XCTAssertFalse(mockStore.mountCalled)
        try await model.saveAll()
        XCTAssertTrue(mockStore.mountCalled)
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    @MainActor func testSaveAllCallsAddMountWhenFlagSet() async throws{
        let share = Share(url: URL(string: "smb://localhost:445/test")!, name: "test", mountPoint: nil, managed: false, connected: .unmounted)
        let exp = expectation(description: "wait for add")
        let mockStore = MockStorage(list:[share],mountResponse: .success("/some/path"), addHandler:{ _ in
            exp.fulfill()
        })
        store = ShareDataModel(storage: mockStore)
        let urlStr = "smb://localhost:445/test"
        let model = AddEditModel(urlString: urlStr, store: store)
        XCTAssertFalse(mockStore.mountCalled)
        try await model.saveAll()
        XCTAssertTrue(mockStore.mountCalled)
        await fulfillment(of: [exp], timeout: 1)
    }

    @MainActor func testSaveAllThrowsURLEmpty() async throws{
        do{
            let model = AddEditModel( store: store)
            try await model.saveAll()
            XCTFail("Should have thrown")
        }catch let err as AddEditModelError{
            guard case .badURL = err else {
                XCTFail("Expected badURL, got \(err)")
                return
            }
        }catch{
            XCTFail("Wrong error")
        }
    }

    // MARK: - Previous Servers

    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "test.addEditModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor func testPreviousServersEmptyByDefault() async throws {
        let defaults = makeTestDefaults()
        let model = AddEditModel(store: store, defaults: defaults)
        XCTAssertEqual(model.previousServers, [])
    }

    @MainActor func testAddServerToHistory() async throws {
        let defaults = makeTestDefaults()
        let model = AddEditModel(urlString: "smb://server/share", store: store, defaults: defaults)
        model.addServerToHistory()
        XCTAssertEqual(model.previousServers, ["smb://server/share"])
    }

    @MainActor func testAddServerToHistoryNoDuplicates() async throws {
        let defaults = makeTestDefaults()
        let model = AddEditModel(urlString: "smb://server/share", store: store, defaults: defaults)
        model.addServerToHistory()
        model.addServerToHistory()
        XCTAssertEqual(model.previousServers, ["smb://server/share"])
    }

    @MainActor func testClearPreviousServers() async throws {
        let defaults = makeTestDefaults()
        let model = AddEditModel(urlString: "smb://server/share", store: store, defaults: defaults)
        model.addServerToHistory()
        XCTAssertFalse(model.previousServers.isEmpty)
        AddEditModel.clearPreviousServers(defaults: defaults)
        XCTAssertEqual(model.previousServers, [])
    }

    @MainActor func testSaveAllAddsToHistory() async throws {
        let defaults = makeTestDefaults()
        let share = Share(url: URL(string: "smb://localhost:445/test")!, name: "test", mountPoint: nil, managed: false, connected: .unmounted)
        let mockStore = MockStorage(list: [share], mountResponse: .success("/some/path"))
        store = ShareDataModel(storage: mockStore)
        let urlStr = "smb://localhost:445/test"
        let model = AddEditModel(urlString: urlStr, store: store, defaults: defaults)
        model.manage = false
        try await model.saveAll()
        XCTAssertEqual(model.previousServers, [urlStr])
    }

    // MARK: - hasPreviousServers

    @MainActor func testHasPreviousServersReturnsFalseWhenEmpty() async throws {
        let defaults = makeTestDefaults()
        XCTAssertFalse(AddEditModel.hasPreviousServers(defaults: defaults))
    }

    @MainActor func testHasPreviousServersReturnsTrueAfterAdd() async throws {
        let defaults = makeTestDefaults()
        let model = AddEditModel(urlString: "smb://server/share", store: store, defaults: defaults)
        model.addServerToHistory()
        XCTAssertTrue(AddEditModel.hasPreviousServers(defaults: defaults))
    }

    @MainActor func testHasPreviousServersReturnsFalseAfterClear() async throws {
        let defaults = makeTestDefaults()
        let model = AddEditModel(urlString: "smb://server/share", store: store, defaults: defaults)
        model.addServerToHistory()
        AddEditModel.clearPreviousServers(defaults: defaults)
        XCTAssertFalse(AddEditModel.hasPreviousServers(defaults: defaults))
    }

    // MARK: - Mount Failure Error Propagation

    @MainActor func testSaveAllThrowsMountFailedOnAuthenticationError() async throws {
        let mockStore = MockStorage(mountResponse: .authenticationError)
        store = ShareDataModel(storage: mockStore)
        let model = AddEditModel(urlString: "smb://localhost:445/test", store: store)
        do {
            try await model.saveAll()
            XCTFail("Should have thrown")
        } catch let err as AddEditModelError {
            guard case .mountFailed(.authenticationError) = err else {
                XCTFail("Expected mountFailed(.authenticationError), got \(err)")
                return
            }
        }
    }

    @MainActor func testSaveAllThrowsMountFailedOnCannotFindHost() async throws {
        let mockStore = MockStorage(mountResponse: .cannotFindHost)
        store = ShareDataModel(storage: mockStore)
        let model = AddEditModel(urlString: "smb://localhost:445/test", store: store)
        do {
            try await model.saveAll()
            XCTFail("Should have thrown")
        } catch let err as AddEditModelError {
            guard case .mountFailed(.cannotFindHost) = err else {
                XCTFail("Expected mountFailed(.cannotFindHost), got \(err)")
                return
            }
        }
    }

    @MainActor func testSaveAllDoesNotAddToHistoryOnFailure() async throws {
        let defaults = makeTestDefaults()
        let mockStore = MockStorage(mountResponse: .timeout)
        store = ShareDataModel(storage: mockStore)
        let model = AddEditModel(urlString: "smb://localhost:445/test", store: store, defaults: defaults)
        do {
            try await model.saveAll()
            XCTFail("Should have thrown")
        } catch {
            // expected
        }
        XCTAssertEqual(model.previousServers, [], "Server should not be added to history on mount failure")
    }

    @MainActor func testLocalizedErrorDescriptions() async throws {
        let authError = AddEditModelError.mountFailed(.authenticationError)
        XCTAssertEqual(authError.localizedDescription, "Authentication failed. Please check your credentials.")

        let hostError = AddEditModelError.mountFailed(.cannotFindHost)
        XCTAssertEqual(hostError.localizedDescription, "Cannot find the server. Please check the address.")

        let timeoutError = AddEditModelError.mountFailed(.timeout)
        XCTAssertEqual(timeoutError.localizedDescription, "The connection timed out.")

        let badURL = AddEditModelError.badURL
        XCTAssertEqual(badURL.localizedDescription, "The URL is invalid.")

        let missingValues = AddEditModelError.missingValues
        XCTAssertEqual(missingValues.localizedDescription, "Missing required values.")
    }

}

