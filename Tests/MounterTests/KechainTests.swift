//
//  KechainTests.swift
//  libMounter
//
//  Created by Mark Tassinari on 2/6/26.
//

import XCTest
@testable import libMounter

final class KechainTests: XCTestCase {
    
    func testSaveRetrieveSuccess() async throws{
        guard let url = URL(string: "smb://test.com:445/share/one") else {XCTFail(); return}
        let keychain = Keychain()
        let account = "test1"
        let pass = "pass"
        do{
            try keychain.save(user: account, password: pass, url: url)
            let saved = try keychain.retrieve(url: url)
            XCTAssertEqual(saved.password, pass)
            XCTAssertEqual(saved.user, account)
            try keychain.delete(url: url)
        }catch{
            XCTFail("error : \(error)")
        }
    }
    func testDeleteSuccess() async throws{
        guard let url = URL(string: "smb://test.com:445/share/one") else {XCTFail(); return}
        let keychain = Keychain()
        let account = "test1"
        let pass = "pass"
        do{
            try keychain.save(user: account, password: pass, url: url)
            let _ = try keychain.retrieve(url: url)
            try keychain.delete(url: url)
            do{
                let _ = try keychain.retrieve(url: url)
                XCTFail("Should throw")
            }catch{
                guard let err = error as? KeychainError else {
                    XCTFail("Should have thrown KeychainError")
                    return
                }
                XCTAssert(err.status == errSecItemNotFound)
            }
        }catch{
            XCTFail("error : \(error)")
        }
    }

   
    func testSaveThrows() async throws{
        let keychain = Keychain()
        guard let url = URL(string: "testcom445//share/one") else {XCTFail(); return}
        XCTAssertThrowsError(try keychain.save(user: "qw", password: "qq", url: url)) { error in
            guard let err = error as? KeychainInputError else {
                XCTFail("Should have thrown KeychainError")
                return
            }
            switch err {
            case .badURL:
                break // expected
           
            }
        }
    }
   
    func testDeleteThrowsBadURL() async throws{
        let keychain = Keychain()
        guard let url = URL(string: "testcom445//share/one") else {XCTFail(); return}
        XCTAssertThrowsError(try keychain.delete(url: url)) { error in
            guard let err = error as? KeychainInputError else {
                XCTFail("Should have thrown KeychainError")
                return
            }
            switch err {
            case .badURL:
                break // expected
        
            }
        }
    }
    func testRetrieveThrowsBadURL() async throws{
        let keychain = Keychain()
        guard let url = URL(string: "testcom445//share/one") else {XCTFail(); return}
        XCTAssertThrowsError(try keychain.retrieve(url: url)) { error in
            guard let err = error as? KeychainInputError else {
                XCTFail("Should have thrown KeychainError")
                return
            }
            switch err {
            case .badURL:
                break // expected
        
            }
        }
    }
   

}
