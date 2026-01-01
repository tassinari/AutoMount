//
//  NewMountModelTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 12/27/25.
//

import XCTest
import Foundation
@testable import MagicMount




final class newModelTests: XCTestCase {
    let defaultsSuiteName = "group.org.tassinari.magicmount.test"
    override func setUpWithError() throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removeObject(forKey: StorageManager.storeKey)
    }

    func testStorageManagerInstantiates() async throws {
        let manager = await StorageManager()
        XCTAssertNotNil(manager)
    }
    @MainActor func testStorageManagerSavesAndLoads() async throws {
        let user = "TestUser"
        let testURl = URL(string: "smb://testUrl")!
        let testPassword = "testPassword"
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let mount = Share(user: user, password: testPassword, url: testURl, name: "name", mountPoint: "/some/share", connected: false)
        try manager.addMount(mount)
        guard let mounts = manager.mounts else {
            XCTFail()
            return
        }
        guard let first = mounts.first else {
            XCTFail()
            return
        }
        XCTAssert(mounts.count == 1)
        XCTAssert(first.url == testURl)
        XCTAssert(first.user == user)
        XCTAssert(first.password  == testPassword)
    
        
    }
    @MainActor func testDeleteMountWorks() async throws {
        let user = "TestUser"
        let testURlStr = "smb://testUrl"
        let testPassword = "testPassword"
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let n = 10
        var expected : [Share] = []
        for i in 0..<n{
            let testURl = URL(string: testURlStr + String(i))!
            let d = Share(user: user, password: testPassword, url: testURl, name: "name", mountPoint: "/some/share", connected: false)
            try manager.addMount(d)
            expected.append(d)
        }
        let j = "3"
        let testURl = URL(string: testURlStr + j)!
        let delete = Share(user: user, password: testPassword, url: testURl, name: "name", mountPoint: "/some/share", connected: false)
        try manager.deleteMount(delete)
        guard let allMounts = manager.mounts else {
            XCTFail()
            return
        }
        
        XCTAssertFalse(allMounts.contains(delete))
        XCTAssert(allMounts.count == n - 1)
        
    }
    @MainActor func testStorageManagerSavesAndLoadsMultiple()  async throws {
        let user = "TestUser"
       
        let testPassword = "testPassword"
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let n = 10
        var expected : [Share] = []
        for i in 0..<n{
            let testURl = URL(string: "smb://testUrl\(i)")!
            let d = Share(user: user + String(i), password: testPassword + String(i), url: testURl, name: "name", mountPoint: "/some/share", connected: false)
            try manager.addMount(d)
            expected.append(d)
        }
        guard let allMounts = manager.mounts else {
            XCTFail()
            return
        }
        XCTAssert(allMounts.count == n)
        XCTAssertEqual(expected.sorted(by: {$0.url.absoluteString > $1.url.absoluteString}), allMounts.sorted(by: {$0.url.absoluteString > $1.url.absoluteString}))
    }
}
    
