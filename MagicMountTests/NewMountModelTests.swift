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
    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: MounterConstants.mountsStorageKey)
    }

    func testStorageManagerInstantiates() async throws {
        let manager = await StorageManager.shared
        XCTAssertNotNil(manager)
    }
    func testStorageManagerSavesAndLoads()  throws {
        let user = "TestUser"
        let testURl = "testUrl"
        let testPassword = "testPassword"
        let manager =  StorageManager.shared
        let mount = MountStorage(user: user, url: testURl, password: testPassword)
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
    func testDeleteMountWorks() throws {
        let user = "TestUser"
        let testURl = "testUrl"
        let testPassword = "testPassword"
        let manager =  StorageManager.shared
        let n = 10
        var expected : [MountStorage] = []
        for i in 0..<n{
            let d = MountStorage(user: user + String(i), url:testURl + String(i), password:testPassword + String(i))
            try manager.addMount(d)
            expected.append(d)
        }
        let j = "3"
        let delete = MountStorage(user: user + j, url: testURl + j, password: testPassword + j)
        try manager.deleteMount(delete)
        guard let allMounts = manager.mounts else {
            XCTFail()
            return
        }
        
        XCTAssertFalse(allMounts.contains(delete))
        XCTAssert(allMounts.count == n - 1)
        
    }
    func testStorageManagerSavesAndLoadsMultiple()  throws {
        let user = "TestUser"
        let testURl = "testUrl"
        let testPassword = "testPassword"
        let manager =  StorageManager.shared
        let n = 10
        var expected : [MountStorage] = []
        for i in 0..<n{
            let d = MountStorage(user: user + String(i), url:testURl + String(i), password:testPassword + String(i))
            try manager.addMount(d)
            expected.append(d)
        }
        guard let allMounts = manager.mounts else {
            XCTFail()
            return
        }
        XCTAssert(allMounts.count == n)
        XCTAssertEqual(expected.sorted(by: {$0.url > $1.url}), allMounts.sorted(by: {$0.url > $1.url}))
    }
}
    
