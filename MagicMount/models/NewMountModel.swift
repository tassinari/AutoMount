import Foundation
import SwiftUI
import libMounter

enum CreateMountState{
    case create, edit
}

enum AddEditModelError : Swift.Error {
    case missingValues
}
@MainActor @Observable final class AddEditModel {
   
    var urlString: String
    var username: String
    var password: String
    private let store : ShareDataModel

    init(urlString: String = "", username: String = "", password: String = "",store: ShareDataModel) {
        self.password = password
        self.urlString = urlString
        self.username = username
        self.store = store
    }

    func clear() {
        urlString = ""
        username = ""
        password = ""
    }
   
    func saveAll() async throws {
        guard !urlString.isEmpty, !username.isEmpty, !password.isEmpty else {
            throw AddEditModelError.missingValues
        }
        let mount = Share(user: username, password: password, url: URL(string: urlString)!, name: "Mount", mountPoint: "/some/path",managed: true, connected: .mounted)
        try await Task {
            try await store.manage(mount)
        }.value
    }
}

