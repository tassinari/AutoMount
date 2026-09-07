//
//  NFSMountTests.swift
//  MounterTests
//
//  Created by Claude on 2/15/26.
//

import XCTest
@testable import libMounter

final class NFSMountTests: BaseTest {

    let hostName = "localhost"
    let port = 2049
    let shareName = "testing"

    override class func setUp() {
//        Self.runPreTestScript(script: "Scripts/dockerNFSMount.sh")
//        let delay = 2.0
        super.setUp()
//        print("Letting NFS server spin up for \(delay) seconds...")
//        let deadline = Date().addingTimeInterval(delay)
//        while Date() < deadline {
//            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
//        }
    }

    override class func tearDown() {
        super.tearDown()
      //  Self.runPreTestScript(script: "Scripts/dockerNFSUnmount.sh")
    }

    override func setUp() async throws {
        try await super.setUp()
        do {
            _ = try await MountData.unmount(url: URL(filePath: "/Volumes/\(shareName)"))
        } catch {
            //no-op, just cleaning up, it may not be mounted and will throw
        }
    }

    override func tearDown() async throws {
        try await super.tearDown()
        do {
            _ = try await MountData.unmount(url: URL(filePath: "/Volumes/\(shareName)"))
        } catch {
            //no-op, just cleaning up, it may not be mounted and will throw
        }
    }

    // MARK: - MountData-level tests

//    @MainActor func testNFSMountAndUnmountWorks() async throws {
//        let mountData = MountData(scheme: "nfs", host: hostName, port: port, path: shareName)
//
//        XCTAssertFalse(FileManager.default.fileExists(atPath: "/Volumes/\(shareName)/test.txt"))
//        do {
//            switch try await mountData.mount() {
//            case .success(_):
//                XCTAssertTrue(FileManager.default.fileExists(atPath: "/Volumes/\(shareName)/test.txt"))
//                guard let share = await storage.fullMountList().first(where: { $0.name == shareName }) else {
//                    XCTFail("Share not found in mount list")
//                    return
//                }
//                try await storage.unmount(share)
//                XCTAssertFalse(FileManager.default.fileExists(atPath: "/Volumes/\(shareName)/test.txt"))
//            default:
//                XCTFail("Expected successful mount")
//            }
//        } catch {
//            XCTFail(error.localizedDescription)
//        }
//    }
//
//    @MainActor func testNFSMountedVolumes() async throws {
//        let mountData = MountData(scheme: "nfs", host: hostName, port: port, path: shareName)
//
//        let _ = try await mountData.mount()
//        try await Task.sleep(nanoseconds: 10000)
//        let volumes = MountInfo.mountedVolumes()
//        guard let test = volumes.first(where: { $0.name == shareName }) else {
//            XCTFail("NFS share not found in mounted volumes")
//            return
//        }
//        XCTAssertEqual(test.name, shareName)
//        XCTAssertEqual(test.path, "/Volumes/\(shareName)")
//    }
//
//    func testNFSMountWithBadHostFails() async throws {
//        let mountData = MountData(scheme: "nfs", host: "UNKNOWN", port: port, path: shareName)
//
//        let result = try await mountData.mount()
//        switch result {
//        case .cannotFindHost:
//            break
//        default:
//            XCTFail("Expected cannotFindHost, got \(result)")
//        }
//    }
//
//    func testNFSMountWithBadShareFails() async throws {
//        let mountData = MountData(scheme: "nfs", host: hostName, port: port, path: "doesntExist")
//
//        let result = try await mountData.mount()
//        switch result {
//        case .success:
//            XCTFail("Expected error for bad share path")
//        default:
//            // Any error response is acceptable for a bad export path
//            break
//        }
//    }
//
//    @MainActor func testNFSAlreadyMountedReportsError() async throws {
//        let mountData = MountData(scheme: "nfs", host: hostName, port: port, path: shareName)
//        _ = try await mountData.mount()
//        switch try await mountData.mount() {
//        case .alreadyMounted:
//            break
//        default:
//            XCTFail("Expected alreadyMounted")
//        }
//    }
//
//    func testNFSIsVolumeMountedReturnsTrueAfterMount() async throws {
//        let mountData = MountData(scheme: "nfs", host: hostName, port: port, path: shareName)
//        XCTAssertFalse(MountInfo.isVolumeMounted(at: URL(filePath: "/Volumes/\(shareName)")))
//
//        let response = try await mountData.mount()
//        switch response {
//        case .success(let mountPath):
//            guard let mountPath else {
//                XCTFail("Expected mount path")
//                return
//            }
//            XCTAssertTrue(MountInfo.isVolumeMounted(at: URL(filePath: mountPath, directoryHint: .isDirectory)))
//        default:
//            XCTFail("Expected success, got \(response)")
//        }
//    }
//
//    // MARK: - Share / StorageManager-level tests
//
//    @MainActor func testNFSShareMountWorks() async throws {
//        let share = Share(
//            url: URL(string: "nfs://localhost:2049/testing")!,
//            name: "testing",
//            mountPoint: "/Volumes/testing",
//            managed: true,
//            connected: .unmounted
//        )
//
//        let result = try await storage.mount(share)
//        switch result {
//        case .success(let mountPath):
//            XCTAssertEqual(mountPath, "/Volumes/testing")
//            XCTAssertTrue(FileManager.default.fileExists(atPath: "/Volumes/testing/test.txt"))
//        default:
//            XCTFail("Expected successful mount, got \(result)")
//        }
//    }
//
//    @MainActor func testNFSFullMountListIncludesMountedShare() async throws {
//        let mountData = MountData(scheme: "nfs", host: hostName, port: port, path: shareName)
//        _ = try await mountData.mount()
//
//        let mounts = await storage.fullMountList()
//        XCTAssertFalse(mounts.isEmpty)
//
//        guard let nfs = mounts.first(where: { $0.name == shareName }) else {
//            XCTFail("NFS share not found in full mount list")
//            return
//        }
//        XCTAssertFalse(nfs.managed)
//        XCTAssertEqual(nfs.mountPoint, "/Volumes/\(shareName)")
//    }
//}
}
