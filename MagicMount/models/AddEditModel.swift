import Foundation
import SwiftUI
import libMounter

enum CreateMountState{
    case create, edit
}

enum AddEditModelError : Swift.Error {
    case missingValues, badURL, mountFailed(MountResponse)
}

extension AddEditModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingValues:
            return "Missing required values."
        case .badURL:
            return "The URL is invalid."
        case .mountFailed(let response):
            switch response {
            case .authenticationError:
                return "Authentication failed. Please check your credentials."
            case .cannotFindHost:
                return "Cannot find the server. Please check the address."
            case .timeout:
                return "The connection timed out."
            case .noSuchFileOrDirectory:
                return "The share was not found on the server."
            case .connectionRefused:
                return "The connection was refused by the server."
            case .alreadyMounted:
                return "This share is already mounted."
            case .genericError(let error):
                return "Mount failed: \(error.localizedDescription)"
            case .success:
                return nil
            }
        }
    }
}
@MainActor @Observable final class AddEditModel {

    var urlString: String
    private let store : ShareDataModel
    var location: String
    var manage: Bool = true
    private let defaults: UserDefaults

    private static let serversKey = "servers"

    init(urlString: String = "", store: ShareDataModel, defaults: UserDefaults = UserDefaults(suiteName: "group.org.tassinari.magicmount") ?? .standard) {
        self.store = store
        self.urlString = urlString
        self.location = ""
        self.defaults = defaults
    }

    var previousServers: [String] {
        defaults.stringArray(forKey: Self.serversKey) ?? []
    }

    func addServerToHistory() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var servers = previousServers
        if !servers.contains(trimmed) {
            servers.append(trimmed)
            defaults.set(servers, forKey: Self.serversKey)
        }
    }

    static func clearPreviousServers(defaults: UserDefaults = UserDefaults(suiteName: "group.org.tassinari.magicmount") ?? .standard) {
        defaults.set([String](), forKey: serversKey)
    }

    func clear() {
        urlString = ""
        location = ""
        manage = true
    }
   
    func saveAll() async throws {
      
        guard let url = URL(string: urlString) else { throw AddEditModelError.badURL }
        let mount = Share( url: url, name: nil, mountPoint: nil,managed: true, connected: .unmounted)
        
        let resp = try await store.mount(mount, ui: true)
        switch resp {
        case .success(_):
            addServerToHistory()
            if manage, let mountedShare = store.shareMatching(url: url){
                try await store.manage(mountedShare)
            }

        default:
            throw AddEditModelError.mountFailed(resp)
        }
//        try await Task {
//            //try await store.manage(mount)
//        }.value
    }
}

