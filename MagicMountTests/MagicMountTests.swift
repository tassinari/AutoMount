//
//  MagicMountTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 12/24/25.
//

import XCTest
@testable import MagicMount

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
            _ = try await unmount(path: "/Volumes/\(shareName)")
        }catch{
            //no-op, just cleaning up, it may not e mounted and will throw
        }
        
    }
    func testURLProducedWithNoPort(){
        let mount = MountData(scheme: .smb, host: "localhost", port: nil, user: "user1", password: "Password1", shareName: "share")
        let expexted = "smb://user1:Password1@localhost:445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    func testURLProducedWithPassword(){
        let mount = MountData(scheme: .smb, host: "localhost", port: 1445, user: "user1", password: "Password1", shareName: "share")
        let expexted = "smb://user1:Password1@localhost:1445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    func testURLProducedWithOutPassword(){
        let mount = MountData(scheme: .smb, host: "localhost", port: 1445, user: nil, password: nil, shareName: "share")
        let expexted = "smb://localhost:1445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    
    
    func testMountWithPasswordWorks() throws{
        let mountData =  MountData(scheme: .smb, host: hostName, port: port, user: userName, password: "secret123", shareName: shareName)
        //FIXME: unmount after every test
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        _ = try mountData.mount()
       
        XCTAssertTrue( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
    }
    func testMountWithPasswordReturnsMountArrayString() throws{
        let mountData =  MountData(scheme: .smb, host: hostName, port: port, user: userName, password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try mountData.mount()
        switch mounts {
        case .success(let mounts):
            XCTAssert(mounts.count == 1)
            XCTAssert(mounts.first == "/Volumes/smbTestShare")
        default:
            XCTFail()
       
        }
       
       
    }
    
    func testMountWithBadUserFails() throws{
        let mountData =  MountData(scheme: .smb, host: hostName, port: port, user: "badName", password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try mountData.mount()
        switch mounts {
        case .authenticationError:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadPasswordFails() throws{
        let mountData =  MountData(scheme: .smb, host: hostName, port: port, user: userName, password: "badpass", shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try mountData.mount()
        switch mounts {
        case .authenticationError:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadHostFails() throws{
        let mountData =  MountData(scheme: .smb, host: "UNKNOWN", port: port, user: userName, password: "badpass", shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try mountData.mount()
        switch mounts {
        case .cannotFindHost:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadPortFails() throws{
        let mountData =  MountData(scheme: .smb, host: hostName, port: 1010, user: userName, password: password, shareName: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try mountData.mount()
        switch mounts {
        case .timeout:
            break
        default:
            XCTFail()
        }
    }
    func testMountWithBadShareFails() throws{
        let mountData =  MountData(scheme: .smb, host: hostName, port: port, user: userName, password: password, shareName: "doesntExsist")
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try mountData.mount()
        switch mounts {
        case .noSuchFileOrDirectory:
            break
        default:
            XCTFail()
        }
    }
    
}


extension MagicMountTests {
    func unmount(path: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["unmount", path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)

                if proc.terminationStatus == 0 {
                    print(output)
                    cont.resume(returning: output)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "DiskUtilError",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output]
                    ))
                }
            }
        }
    }
}
