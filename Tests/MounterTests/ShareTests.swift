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
        let state = await share.getConnected()
        XCTAssert(state == .mounted)
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
            managed: true,
            connected: .unmounting
        )
        try await storage.unmount(share)
        let state = await share.getConnected()
        XCTAssert(state == .unmounting)
        
        
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
            user: "samba",
            password: "",
            url: URL(string: "smb://samba@ecample.com:1445/smbTestShare")!,
            name: "smbTestShare",
            mountPoint: "/Volumes/DOESNTEXSIST",
            managed: true,
            connected: .unmounted
        )
        var currentPass = await share.getPassword()
        var currentUser = await share.getUser()
        var currentManaged = await share.getManaged()
        var currentStatus = await share.getConnected()
        
        XCTAssertNotEqual(currentPass, p)
        XCTAssertNotEqual(currentUser, u)
        XCTAssertNotEqual(currentManaged, false)
        XCTAssertNotEqual(currentStatus, .mounted)
        
        await share.setUser(u)
        await share.setPassword(p)
        await share.setManaged(false)
        await share.setConnected(.mounted)
        
        currentPass = await share.getPassword()
        currentUser = await share.getUser()
        currentManaged = await share.getManaged()
        currentStatus = await share.getConnected()
        
        XCTAssertEqual(currentPass, p)
        XCTAssertEqual(currentUser, u)
        XCTAssertEqual(currentManaged, false)
        XCTAssertEqual(currentStatus, .mounted)
        
        let data = try JSONEncoder().encode(share)
        let share2 = try JSONDecoder().decode(Share.self, from: data)
        
        
        let currentPass2 = await share2.getPassword()
        let currentUser2 = await share2.getUser()
        let currentManaged2 = await share2.getManaged()
        let currentStatus2 = await share2.getConnected()
        
        XCTAssertEqual(currentPass2, p)
        XCTAssertEqual(currentUser2, u)
        XCTAssertEqual(currentManaged2, false)
        XCTAssertEqual(currentStatus2, .mounted)
        
      
    }

}
