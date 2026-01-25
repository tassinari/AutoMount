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
            connected: .mounted
        )

        let mountData = share.mountData

        XCTAssertEqual(mountData?.scheme, "smb")
        XCTAssertEqual(mountData?.host, "localhost")
        XCTAssertEqual(mountData?.port, 1445)
        XCTAssertEqual(mountData?.user, "samba")
        XCTAssertEqual(mountData?.shareName, "smbTestShare")
        XCTAssertEqual(share.connected, .mounted)
    }
    
    @MainActor
    func testShareMountWorks() async throws {
        let share = Share(  user: "samba",
                            password: "",
                            url: URL(string: "smb://samba:secret123@localhost:1445/smbTestShare")!,
                            name: "smbTestShare",
                            mountPoint: "/Volumes/smbTestShare", managed: true,
                            connected: .unmounted
        )
        
        let result = try await share.mount()

        switch result {
        case .success(let share):
            XCTAssertTrue(share.mountPoint == "/Volumes/smbTestShare")
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: "/Volumes/smbTestShare/empty_file.txt"
            ))
        default:
            XCTFail("Expected successful mount")
        }
    }
    @MainActor
    func testShareMountThrowsNoMountData() async throws {
        let share = Share(  user: "samba",
                            password: "",
                            url: URL(filePath: ""),
                            name: "smbTestShare",
                            mountPoint: "/Volumes/smbTestShare", managed: true,
                            connected: .unmounted
        )
       
        do{
            let _ = try await share.mount()
            XCTFail("should have thrown")
        }catch let error as MountError{
            XCTAssert(error == .noMountData)
        }catch{
            XCTFail("Wrong error \(String(describing: error))")
        }
    
    }
    @MainActor
    func testShareMountReturnsAlreadyMounted() async throws {
        let share = Share(  user: "samba",
                            password: "",
                            url: URL(string: "smb://samba:secret123@localhost:1445/smbTestShare")!,
                            name: "smbTestShare",
                            mountPoint: "/Volumes/smbTestShare", managed: true,
                            connected: .mounted
        )
       
        do{
            let r = try await share.mount()
            switch r{
            case .alreadyMounted:
                break
            default:
                XCTFail()
            }
            
        }catch{
            XCTFail("error \(String(describing: error))")
        }
    
    }
    func testUnmountingDoesNothingWhenAlreadyUnmounting() async throws {
        let share = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@localhost:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/smbTestShare",
            managed: true,
            connected: .unmounting
        )
        try await share.unmount()
        XCTAssert(share.connected == .unmounting)
        
        
    }
    func testUnmountingThrowsWhenWrongFile() async throws {
        let share = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@localhost:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .mounted
        )
       
        do{
            try await share.unmount()
            XCTFail("Should have thrown")
        }catch let error as NSError{
            XCTAssertTrue(error.domain == NSCocoaErrorDomain)
            XCTAssertTrue(error.code == 4)
        }
        
        
    }
    func testEqualAndHash(){
        let share1 = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@localhost:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        let share2 = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@localhost:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        let share3 = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        let set1 : Set<Share> = [share1,share2]
        let set2 : Set<Share> = [share2,share3]
        XCTAssertEqual(share1, share2)
        XCTAssertNotEqual(share1, share3)
        XCTAssertNotEqual(set1, set2)
        XCTAssertEqual(share1.id,share2.id)
    }
    

}
