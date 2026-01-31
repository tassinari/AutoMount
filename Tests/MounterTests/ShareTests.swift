//
//  ShareTests.swift
//  libMounter
//
//  Created by Mark Tassinari on 1/19/26.
//


import XCTest
@testable import libMounter

final class ShareTests: BaseTest {

    func testShareProducesCorrectMountData() async throws{
     
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
        
        let result = try await storage.mount(share)

        switch result {
        case .success(let shareName):
            XCTAssertTrue(shareName == "/Volumes/smbTestShare")
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
            let _ = try await storage.mount(share)
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
            let r = try await storage.mount(share)
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
    @MainActor func testUnmountingDoesNothingWhenAlreadyUnmounting() async throws {
        let share = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@localhost:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/smbTestShare",
            managed: false,
            connected: .unmounting
        )
        let _ = try await storage.mount(share)
        
        //try to unmount, its a no op, its really  mounted, should still be there
        try await storage.unmount(share)
        let mountedShare = await storage.fullMountList().first(where: {$0.name == share.name})
        XCTAssertNotNil(mountedShare)
        XCTAssert(mountedShare?.connected == .mounted)
    }
    @MainActor func testUnmountingThrowsWhenWrongFile() async throws {
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
            try await storage.unmount(share)
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
    func testTypeCorrect() async throws{
        let share = Share(
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        
        XCTAssertTrue(share.type == "smb")
        let share2 = Share(
            user: "samba",
            password: "",
            url: URL(string: "afp://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        
        XCTAssertTrue(share2.type == "afp")
    }
    
    func testEncodeDecodeWithSnapshotWorking() async throws{
        let u = "user2"
        let p = "pass2"
        let share = Share(
            user: u,
            password: p,
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        XCTAssertEqual(share.password, p)
        XCTAssertEqual(share.user, u)
        XCTAssertEqual(share.managed, true)
        XCTAssertEqual(share.connected, .unmounted)
        
        
        let data = try JSONEncoder().encode(share)
        let share2 = try JSONDecoder().decode(Share.self, from: data)
        
        XCTAssertEqual(share2.password, p)
        XCTAssertEqual(share2.user, u)
        XCTAssertEqual(share2.managed, true)
        XCTAssertEqual(share2.connected, .unmounted)
        
      
    }
    func testManagedCopyWorks() async throws{
        let u = "user2"
        let p = "pass2"
        let share = Share(
            user: u,
            password: p,
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: false,
            connected: .unmounted
        )
        XCTAssertTrue(share.managedCopy.managed)
    }
    func testUnManagedCopyWorks() async throws{
        let u = "user2"
        let p = "pass2"
        let share = Share(
            user: u,
            password: p,
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        XCTAssertFalse(share.unmanagedCopy.managed)
    }
    func testConnectedCopyWorks() async throws{
        let u = "user2"
        let p = "pass2"
        let share = Share(
            user: u,
            password: p,
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: false,
            connected: .unmounted
        )
        XCTAssertTrue(share.mountedCopy.connected == .mounted)
    }
    func testNonConnectedCopyWorks() async throws{
        let u = "user2"
        let p = "pass2"
        let share = Share(
            user: u,
            password: p,
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .mounted
        )
        XCTAssertTrue(share.unmountedCopy.connected == .unmounted)
    }

}
