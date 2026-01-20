//
//  StorageManagerTests.swift
//  Mounter
//
//  Created by Mark Tassinari on 1/19/26.
//

import XCTest
@testable import libMounter

final class StorageManagerTests: BaseTest {
    let defaultsSuiteName = "group.org.tassinari.magicmount.test"
    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults(suiteName: defaultsSuiteName)?.removeObject(forKey: StorageManager.storeKey)
    }

    @MainActor func testStorageManagerSavesAndLoads()   async throws {
        let user = "TestUser"
        let testURL = URL(string: "testUrl")!
        let testPassword = "testPassword"
        let name = "testName"
        
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let mount = Share(user: user, password: testPassword, url: testURL, name: name, mountPoint: "/Volumes/share", managed: true, connected: true)
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
        XCTAssert(first.url == testURL)
        XCTAssert(first.user == user)
        XCTAssert(first.password  == testPassword)
    
        
    }
    @MainActor func testStorageManagerTHrowsWithNoDefaults()   async throws {
        let user = "TestUser"
        let testURL = URL(string: "testUrl")!
        let testPassword = "testPassword"
        let name = "testName"
       
        let manager =  StorageManager(defaults: nil)
        let mount = Share(user: user, password: testPassword, url: testURL, name: name, mountPoint: "/Volumes/share",managed: true, connected: true)
        do{
            try manager.addMount(mount)
            XCTFail("should have thrown")
        }catch let e as StorageManagerError{
            XCTAssert(e == StorageManagerError.noUserDefaults)
        }catch{
            XCTFail()
        }
    }
    @MainActor func testStorageManagerThrowsOnDeleteWithNoDefaults()   async throws {
        let user = "TestUser"
        let testURL = URL(string: "testUrl")!
        let testPassword = "testPassword"
        let name = "testName"
        let manager =  StorageManager(defaults: nil)
        let mount = Share(user: user, password: testPassword, url: testURL, name: name, mountPoint: "/Volumes/share",managed: true, connected: true)
        do{
            try manager.deleteMount(mount)
            XCTFail("should have thrown")
        }catch let e as StorageManagerError{
            XCTAssert(e == StorageManagerError.noUserDefaults)
        }catch{
            XCTFail()
        }
    }
    @MainActor func testStorageManagerNilWithNoDefaults()   async throws {
        let manager =  StorageManager(defaults: nil)
        
        let mounts = manager.mounts
        XCTAssertNil(mounts)
        
    }
    @MainActor func testStorageManagerDeleteThrowsWithNoKey()   async throws {
        let user = "TestUser"
        let testURL = URL(string: "testUrl")!
        let testPassword = "testPassword"
        let name = "testName"
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let mount = Share(user: user, password: testPassword, url: testURL, name: name, mountPoint: "/Volumes/share",managed: true, connected: true)
        do{
            try manager.deleteMount(mount)
            XCTFail("should have thrown")
        }catch let e as StorageManagerError{
            XCTAssert(e == StorageManagerError.doesNotExsist)
        }catch{
            XCTFail()
        }
        
    }
    @MainActor func testDeleteMountWorks() async throws {
        let user = "TestUser"

        let testPassword = "testPassword"
        let name = "testName"
        let uuid = UUID().uuidString
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let n = 10
        var expected : [Share] = []
        for i in 0..<n{
            let testURL = URL(string: "testUrl\(i)")!
            let d = Share(user: user, password: testPassword, url: testURL, name: name, mountPoint: "/Volumes/share",managed: true, connected: true)
            try manager.addMount(d)
            expected.append(d)
        }
        let j = "3"
        let delete = Share(user: user, password: testPassword, url: URL(string: "testUrl\(j)")!, name: name, mountPoint: "/Volumes/share",managed: true, connected: true)
        try manager.deleteMount(delete)
        guard let allMounts = manager.mounts else {
            XCTFail()
            return
        }
        
        XCTAssertFalse(allMounts.contains(delete))
        XCTAssert(allMounts.count == n - 1)
        
    }
    @MainActor func testStorageManagerSavesAndLoadsMultiple()   async throws {
        let user = "TestUser"
        
        let testPassword = "testPassword"
        let name = "testName"
        let manager =  StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
        let n = 10
        var expected : [Share] = []
        for i in 0..<n{
            let testURL = URL(string: "testUrl\(i)")!
            let d = Share(user: user, password: testPassword, url: testURL, name: name, mountPoint: "/Volumes/share",managed: true, connected: true)
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
    func testFullMountListIncludesMountedSMBShare() async throws {
        let mountData = MountData(
            scheme: "smb",
            host: "localhost",
            port: 1445,
            user: "samba",
            password: "secret123",
            shareName: "smbTestShare"
        )

        _ = try await mountData.mount()

        guard let mounts = StorageManager().fullMountList else{  XCTFail(); return}

        XCTAssertFalse(mounts.isEmpty)

        let smb = mounts.first { $0.name == "smbTestShare" }
        XCTAssertNotNil(smb)
        XCTAssertEqual(smb?.mountPoint, "/Volumes/smbTestShare")
    }


}
