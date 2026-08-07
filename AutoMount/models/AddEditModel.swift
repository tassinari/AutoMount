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
            return String(localized: "error.missing_values")
        case .badURL:
            return String(localized: "error.bad_url")
        case .mountFailed(let response):
            switch response {
            case .authenticationError:
                return String(localized: "error.auth_failed")
            case .cannotFindHost:
                return String(localized: "error.host_not_found")
            case .timeout:
                return String(localized: "error.timeout")
            case .noSuchFileOrDirectory:
                return String(localized: "error.share_not_found")
            case .connectionRefused:
                return String(localized: "error.connection_refused")
            case .alreadyMounted:
                return String(localized: "error.already_mounted")
            case .genericError(let error):
                return String(localized: "error.mount_generic \(error.localizedDescription)")
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

   

    init(urlString: String = "", store: ShareDataModel, defaults: UserDefaults = UserDefaults(suiteName: "group.org.tassinari.magicmount") ?? .standard) {
        self.store = store
        self.urlString = urlString
        self.location = ""
        self.defaults = defaults
    }

    var previousServers: [String] {
        defaults.stringArray(forKey: Constant.serversKey) ?? []
    }

    func addServerToHistory() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var servers = previousServers
        if !servers.contains(trimmed) {
            servers.append(trimmed)
            defaults.set(servers, forKey: Constant.serversKey)
            defaults.set(servers.isEmpty, forKey: Constant.serverEmptyKey)
        }
    }

    static func clearPreviousServers(defaults: UserDefaults = UserDefaults(suiteName: "group.org.tassinari.magicmount") ?? .standard) {
        defaults.set([String](), forKey: Constant.serversKey)
        defaults.set(true, forKey: Constant.serverEmptyKey)
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

