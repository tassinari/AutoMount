//
//  File.swift
//  libMounter
//
//  Created by Mark Tassinari on 2/6/26.
//

import Foundation
import Security

struct KeychainError: Error, CustomStringConvertible {

    let status: OSStatus
    init(_ status: OSStatus) {
        self.status = status
    }
    var description: String {
        if let message = SecCopyErrorMessageString(status, nil) {
            return message as String
        }
        return "Keychain error: \(status)"
    }
}
enum KeychainInputError: Error {
    case badURL
}

struct KeyChainResult{
    let user: String
    let password: String
}

class Keychain {
    
    let domain : String = "org.tassinari.libmounter"
    
    func save(user: String, password: String, url: URL) throws{
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              let scheme = components.scheme
        else{
            throw KeychainInputError.badURL
        }
        let passwordData = Data(password.utf8)
        
        // Remove existing first (important)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: domain,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: user,
            kSecAttrPath as String: components.path
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: domain,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: user,
            kSecValueData as String: passwordData,
            kSecAttrProtocol as String: scheme,
            kSecAttrPath as String: components.path,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if let port = components.port {
            addQuery[kSecAttrPort as String] = String(port)
        }
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError(status)
        }
    }
    func delete(url: URL) throws{
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              let scheme = components.scheme
        else{
            throw KeychainInputError.badURL
        }
        let deleteQuery: [String: Any] = [
            kSecAttrService as String: domain,
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: scheme,
            kSecAttrPath as String: components.path
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
    }
    func retrieve(url: URL) throws -> KeyChainResult{
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              let scheme = components.scheme
        else{
            throw KeychainInputError.badURL
        }
        let query: [String: Any] = [
            kSecAttrService as String: domain,
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: scheme,
            kSecAttrPath as String: components.path,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        guard status == errSecSuccess else {
            throw KeychainError(status)
        }
        
        guard
            let item = result as? [String: Any],
            let user = item[kSecAttrAccount as String] as? String,
                // Password
            let data = item[kSecValueData as String] as? Data
                
        else {
            throw KeychainError(errSecDecode)
        }
        let password = String(decoding: data, as: UTF8.self)
        return KeyChainResult(user: user, password: password)
    }
}
