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
    var store : ShareDataModel!
    
    @MainActor override func setUpWithError() throws {
        store = ShareDataModel(storage: MockStorage())
    }
   
    
    @MainActor func testInitEmpty() async throws{
        let model = AddEditModel(store: store)
        XCTAssertEqual(model.urlString, "")
      
    }
    @MainActor func testInitHoldsAllValues() async throws{
        let url = "urlString"
        let user = "username"
        let pass = "password"
        
        let model = AddEditModel(urlString: url, store: store)
        XCTAssertEqual(model.urlString, url)
       
    }
    @MainActor func testClearWorks() async throws{
        let url = "urlString"
        let user = "username"
        let pass = "password"
        
        let model = AddEditModel(urlString: url,  store: store)
        XCTAssertEqual(model.urlString, url)
    
        model.clear()
        XCTAssertEqual(model.urlString, "")
   
        
    }
    @MainActor func testSaveAllWorks() async throws{
        let urlStr = "smb://localhost:445/test"
        guard let url = URL(string: urlStr) else {XCTFail(); return}
      
        let model = AddEditModel(urlString: urlStr, store: store)
        try await model.saveAll()
        
        guard let share = await StorageManager().fullMountList().first else {XCTFail(); return}
        
        XCTAssertEqual(share.url, url)
    }
    @MainActor func testSaveAllThrowsAllEmpty() async throws{
        do{
            let model = AddEditModel(store: store)
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
            let model = AddEditModel( store: store)
            try await model.saveAll()
            XCTFail("Should have thrown")
        }catch let err as AddEditModelError{
            XCTAssertEqual(err, AddEditModelError.missingValues)
            
        }catch{
            XCTFail("Wrong error")
        }
    }
    

}
    
