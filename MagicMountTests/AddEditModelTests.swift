//
//  NewMountModelTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 12/27/25.
//

import XCTest
import Foundation
import libMounter
@testable import MagicMount




final class AddEditModelTests: XCTestCase {
   
    
    @MainActor func testInitEmpty() async throws{
        let model = AddEditModel()
        XCTAssertEqual(model.urlString, "")
        XCTAssertEqual(model.username, "")
        XCTAssertEqual(model.password, "")
    }
    @MainActor func testInitHoldsAllValues() async throws{
        let url = "urlString"
        let user = "username"
        let pass = "password"
        
        let model = AddEditModel(urlString: url, username: user, password: pass)
        XCTAssertEqual(model.urlString, url)
        XCTAssertEqual(model.username, user)
        XCTAssertEqual(model.password, pass)
    }
    @MainActor func testClearWorks() async throws{
        let url = "urlString"
        let user = "username"
        let pass = "password"
        
        let model = AddEditModel(urlString: url, username: user, password: pass)
        XCTAssertEqual(model.urlString, url)
        XCTAssertEqual(model.username, user)
        XCTAssertEqual(model.password, pass)
        model.clear()
        XCTAssertEqual(model.urlString, "")
        XCTAssertEqual(model.username, "")
        XCTAssertEqual(model.password, "")
        
    }
    @MainActor func testSaveAllWorks() async throws{
        let urlStr = "smb://localhost:445/test"
        guard let url = URL(string: urlStr) else {XCTFail(); return}
        let user = "username"
        let pass = "password"
        
        let model = AddEditModel(urlString: urlStr, username: user, password: pass)
        try await model.saveAll()
        
        guard let share = await StorageManager().fullMountList().first else {XCTFail(); return}
        
        XCTAssertEqual(share.user, user)
        XCTAssertEqual(share.password, pass)
        XCTAssertEqual(share.url, url)
    }
    @MainActor func testSaveAllThrowsAllEmpty() async throws{
        do{
            let model = AddEditModel()
            try await model.saveAll()
            XCTFail("Should have thrown")
        }catch let err as AddEditModelError{
            XCTAssertEqual(err, AddEditModelError.missingValues)
            
        }catch{
            XCTFail("Wrong error")
        }
    }
    @MainActor func testSaveAllThrowsURLEmpty() async throws{
        do{
            let model = AddEditModel(username: "dde", password: "cdxc")
            try await model.saveAll()
            XCTFail("Should have thrown")
        }catch let err as AddEditModelError{
            XCTAssertEqual(err, AddEditModelError.missingValues)
            
        }catch{
            XCTFail("Wrong error")
        }
    }
    

}
    
