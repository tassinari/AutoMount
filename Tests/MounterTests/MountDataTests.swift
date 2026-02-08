//
//  MountDataTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 12/24/25.
//

import XCTest
@testable import libMounter

enum ShellError: Error {
    case nonZeroExit(Int, String)
}

class BaseTest : XCTestCase{
    static let defaultsSuiteName = "group.org.tassinari.magicmount.test"
    let hostName = "localhost"
    let port = 1445
    let password = "secret123"
    let userName = "samba"
    let shareName = "smbTestShare"
    let storage = StorageManager(defaults: UserDefaults(suiteName: defaultsSuiteName))
    
    static func runPreTestScript(script: String) {
        do {
            let tmpLocation = FileManager.default.temporaryDirectory.appending(path: "mount", directoryHint: .isDirectory)
            
            try FileManager.default.createDirectory(at: tmpLocation, withIntermediateDirectories: true)
            XCTAssert( FileManager.default.fileExists(atPath: tmpLocation.path()))
            let testFileURL = URL(fileURLWithPath: #filePath)
            let packageRoot = testFileURL
                .deletingLastPathComponent() // MounterTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // package root
            
            let scriptURL = packageRoot
                .appendingPathComponent(script)
            
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: scriptURL.path),
                "dockerMount.sh is missing or not executable"
            )
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path, tmpLocation.path()]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            
            try process.run()
            process.waitUntilExit()
            
            
//            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
//            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
//            
//            if let stdout = String(data: stdoutData, encoding: .utf8), !stdout.isEmpty {
//                print("📤 pretest.sh stdout:\n\(stdout)")
//            }
//
//            if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
//                print("📥 pretest.sh stderr:\n\(stderr)")
//            }
            
            XCTAssertEqual(
                process.terminationStatus,
                0,
                "dockerMount.sh exited with code \(process.terminationStatus)"
            )
        } catch {
            XCTFail("Failed to run script: \(error)")
            return
        }
    }
    override class func tearDown() {
        super.tearDown()
        Self.runPreTestScript(script: "Scripts/dockerUnmount.sh")
    }
    
    override class func setUp() {
        
        Self.runPreTestScript(script: "Scripts/dockerMount.sh")
        
        let delay = 2.0
        super.setUp()
        print("Letting smb server spin up for \(delay) seconds...")
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
    override func setUp() async throws {
        for m in  await storage.mounts() ?? []{
            try await storage.unmount(m)
        }
        
    }
    
}



final class MountDataTests: BaseTest {


    
    override func setUp() async throws {
        try await super.setUp()
        do{
            _ = try await MountData.unmount(url: URL(filePath: "/Volumes/\(shareName)"))
        }catch{
            //no-op, just cleaning up, it may not e mounted and will throw
        }
        
    }
    override func tearDown() async throws {
        try await super.tearDown()
        do{
            _ = try await MountData.unmount(url: URL(filePath: "/Volumes/\(shareName)"))
        }catch{
            //no-op, just cleaning up, it may not e mounted and will throw
        }
        
    }
//    func testMultiConnect() async throws{
//        let mount = MountData(scheme: "smb", host: "synology", port: nil, user: "tassinari", password: "mar4721k", path: "")
//        let expexted = "smb://tassinari:mar4721k@synology:445"
//        //XCTAssertEqual(expexted, try mount.url.absoluteString)
//        print(try mount.url.absoluteString)
//        do{
//            let r = try await  mount.mount()
//            switch r{
//                
//            case .genericError(let e):
//                print(String(describing: e))
//            case .success(let str):
//                print(str)
//            case .authenticationError:
//                break
//            case .cannotFindHost:
//                break
//            case .timeout:
//                break
//            case .noSuchFileOrDirectory:
//                break
//            case .connectionRefused:
//                break
//            case .alreadyMounted:
//                break
//            }
//        }catch{
//            print(String(describing: error))
//        }
//    }
    func testURLProducedWithNoPort(){
        let mount = MountData(scheme: "smb", host: "localhost", port: nil, user: "user1", password: "Password1", path: "share")
        let expexted = "smb://localhost:445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    func testURLProducedWithPassword(){
        let mount = MountData(scheme: "smb", host: "localhost", port: 1445, user: "user1", password: "Password1", path: "share")
        let expexted = "smb://localhost:1445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    func testURLProducedWithOutPassword(){
        let mount = MountData(scheme: "smb", host: "localhost", port: 1445, user: nil, password: nil, path: "share")
        let expexted = "smb://localhost:1445/share"
        XCTAssertEqual(expexted, try mount.url.absoluteString)
    }
    
    
    @MainActor func testMountWithPasswordWorks() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "secret123", path: shareName)
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
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: password, path: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .success(let shareName):
            XCTAssert(shareName == "/Volumes/smbTestShare")
        default:
            XCTFail()
            
        }
        
        
    }
    @MainActor func testUnmountWorks() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "secret123", path: shareName)
        //FIXME: unmount after every test
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        do{
            switch try await mountData.mount(){
            case .success( _):
                guard let share = await storage.fullMountList().first(where: {$0.name == shareName}) else {XCTFail(); return}
                XCTAssertTrue( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
                try await storage.unmount( share)
                XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
            default:
                XCTFail()
            }
            
            
        }catch{
            XCTFail(error.localizedDescription)
        }
        
        
    }
    
    @MainActor func testMountedVolumes() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: password, path: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let _ = try await mountData.mount()
        try await Task.sleep(nanoseconds: 10000)
        let volumes = MountInfo.mountedVolumes()
        guard let test = volumes.first(where: { $0.name == shareName}) else { XCTFail() ; return}
        XCTAssertEqual(test.remountURL, URL(string: "smb://samba@localhost:1445/smbTestShare")!)
        XCTAssertEqual(test.name, shareName)
        XCTAssertEqual(test.path, "/Volumes/\(shareName)")
        
    }
    
    func testMountWithWrongPortFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: 445, user: userName, password: password, path: shareName)
        
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
        let mountData =  MountData(scheme: "smb", host: "UNKNOWN", port: port, user: userName, password: "badpass", path: shareName)
        
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
        let mountData =  MountData(scheme: "smb", host: hostName, port: 1010, user: userName, password: password, path: shareName)
        
        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        let mounts = try await mountData.mount()
        switch mounts {
        case .timeout:
            break
        default:
            XCTFail("Got \(mounts)")
        }
    }
    func testMountWithBadShareFails() async throws{
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: password, path: "doesntExsist")
        
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
        let mountData =  MountData(scheme: "smb", host: hostName, port: port, user: userName, password: "secret123", path: shareName)
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
        //        let mountData =  MountData(scheme: "smb", host: "synology", port: 445, user: "tassinaeri", password: nil, path: "media")
        //        print(try mountData.url)
        //        XCTAssertFalse( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
        //        _ = try mountData.mount()
        //
        //        XCTAssertTrue( FileManager.default.fileExists(atPath: "/Volumes/smbTestShare/empty_file.txt"))
    }
    
    func testIsVolumeMountedReturnsTrueAfterMount() async throws {
        let mountData = MountData(
            scheme: "smb",
            host: "localhost",
            port: 1445,
            user: "samba",
            password: "secret123",
            path: "smbTestShare"
        )
        XCTAssertFalse(MountInfo.isVolumeMounted(at: URL(filePath: "/Volumes/smbTestShare")))

        let response = try await mountData.mount()
        switch response{
        case .success(let shareName):
            guard let shareName else {
                XCTFail("Expected share name")
                return
            }
            XCTAssertTrue(MountInfo.isVolumeMounted(at: URL(filePath: shareName, directoryHint: .isDirectory)))
        default:
            XCTFail()
        }


        
    }

}


