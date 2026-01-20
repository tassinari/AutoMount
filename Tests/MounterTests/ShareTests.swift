//
//  ShareTests.swift
//  libMounter
//
//  Created by Mark Tassinari on 1/19/26.
//


import XCTest
@testable import libMounter

final class ShareTests: BaseTest {

    func testShareProducesCorrectMountData() {
        let share = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@localhost:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/smbTestShare",
            managed: true,
            connected: true
        )

        let mountData = share.mountData

        XCTAssertEqual(mountData?.scheme, "smb")
        XCTAssertEqual(mountData?.host, "localhost")
        XCTAssertEqual(mountData?.port, 1445)
        XCTAssertEqual(mountData?.user, "samba")
        XCTAssertEqual(mountData?.shareName, "smbTestShare")
    }
    
    @MainActor
    func testShareMountWorks() async throws {
        let share = Share(  user: "samba",
                            password: "",
                            url: URL(string: "smb://samba:secret123@localhost:1445/smbTestShare")!,
                            name: "smbTestShare",
                            mountPoint: "/Volumes/smbTestShare", managed: true,
                            connected: true
        )
        
        let result = try await share.mount()

        switch result {
        case .success(let mounts):
            XCTAssertTrue(mounts.contains("/Volumes/smbTestShare"))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: "/Volumes/smbTestShare/empty_file.txt"
            ))
        default:
            XCTFail("Expected successful mount")
        }
    }

}
