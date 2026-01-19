//
//  MagicMountTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 12/24/25.
//

import XCTest
@testable import MagicMountBackground

enum ShellError: Error {
    case nonZeroExit(Int, String)
}



final class MagicMountTests: XCTestCase {
    
    let hostName = "localhost"
    let port = 1445
    let password = "secret123"
    let userName = "samba"
    let shareName = "smbTestShare"
    
    override class func setUp() {
        let delay = 2.0
        super.setUp()
        print("Letting smb server spin up for \(delay) seconds...")
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
    override func setUp() async throws {
        try await super.setUp()
        
    }
    override func tearDown() async throws {
        try await super.tearDown()
        do{
            _ = try await MountData.unmount(url: URL(filePath: "/Volumes/\(shareName)"))
        }catch{
            //no-op, just cleaning up, it may not e mounted and will throw
        }
        
    }
    func testURLProducedWithNoPort(){
        let mount = MountData(scheme: "smb", host: "localhost", port: nil, user: "user1", password: "Password1", shareName: "share")
        let expexted = "smb://user1:Password1@localhost:445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    func testURLProducedWithPassword(){
        let mount = MountData(scheme: "smb", host: "localhost", port: 1445, user: "user1", password: "Password1", shareName: "share")
        let expexted = "smb://user1:Password1@localhost:1445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    func testURLProducedWithOutPassword(){
        let mount = MountData(scheme: "smb", host: "localhost", port: 1445, user: nil, password: nil, shareName: "share")
        let expexted = "smb://localhost:1445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    
    
    @MainActor func testMountWithPasswordWorks() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "secret123", shareName: shareName)
        //FIXME: unmount after every test
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        do{
            _ = try await mountData.mount()
        }catch{
            XCTFail(error.localizedDescription)
        }
       
        XCTAssertTrue( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
    }
    func testMountWithPasswordReturnsMountArrayString() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .success(let mounts):
            XCTAssert(mounts.count == 1)
            XCTAssert(mounts.first == "/Volumes/smbTestShare")
        default:
            XCTFail()
       
        }
       
       
    }
    @MainActor func testUnmountWorks() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "secret123", shareName: shareName)
        //FIXME: unmount after every test
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        do{
            switch try await mountData.mount(){
            case .success( _):
                XCTAssertTrue( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
                guard let share = MountInfo.mountedVolumes().first(where: ({$0.name == shareName})) else {XCTFail(); return}
                try await share.unmount()
                XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
            default:
                XCTFail()
            }
            
           
        }catch{
            XCTFail(error.localizedDescription)
        }
        
       
    }
    
    @MainActor func testMountedVolumes() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let _ = try await mountData.mount()
        let volumes = MountInfo.mountedVolumes()
        XCTAssert(volumes.count > 1) //one for test mount and one for mac HD
        guard let test = volumes.first(where: { $0.name == shareName}) else { XCTFail() ; return}
        XCTAssertEqual(test.url, URL(string: "smb://samba@localhost:1445/smbTestShare")!)
        XCTAssertEqual(test.name, shareName)
        XCTAssertEqual(test.mountPoint, "/Volumes/\(shareName)")
       
    }

    func testMountWithBadUserFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: "badName", password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .authenticationError:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadPasswordFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "badpass", shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .authenticationError:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithWrongPortFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: 445, user: userName, password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .connectionRefused:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadHostFails() async throws{
        let mountData =  MountData(scheme: "smb", host: "UNKNOWN", port: port, user: userName, password: "badpass", shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .cannotFindHost:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithRandomPortFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: 1010, user: userName, password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .timeout:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadShareFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: password, shareName: "doesntExsist")
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .noSuchFileOrDirectory:
            break
        default:
            XCTFail()
        }
    }
    @MainActor func testAlreadyMountedReportsError() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "secret123", shareName: shareName)
        _ = try await mountData.mount()
        switch try await mountData.mount() {
        case .alreadyMounted:
            break
        default:
            XCTFail()
        }
    }
    
    //
    func testLiveMountWithPasswordWorks() async throws{
//        let mountData =  MountData(scheme: "smb", host: "synology", port: 445, user: "tassinaeri", password: nil, shareName: "media")
//        print(try mountData.url)
//        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
//        _ = try mountData.mount()
//       
//        XCTAssertTrue( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
    }
}

