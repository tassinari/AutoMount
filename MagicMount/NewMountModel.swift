import Foundation
import SwiftUI
import libMounter

enum NewMountModelError : Swift.Error {
    case missingValues
}
@MainActor @Observable final class CreateMountModel {
   
    var urlString: String
    var username: String
    var password: String

    init(urlString: String = "", username: String = "", password: String = "") {
        self.password = password
        self.urlString = urlString
        self.username = username
    }

    func clear() {
        urlString = ""
        username = ""
        password = ""
    }
   
    func saveAll() async throws {
        guard !urlString.isEmpty, !username.isEmpty, !password.isEmpty else {
            throw NewMountModelError.missingValues
        }

        let mount = Share(user: username, password: password, url: URL(string: urlString)!, name: "Mount", mountPoint: "/some/path",managed: true, connected: false)

        try await Task {
            try StorageManager().addMount(mount)
        }.value
    }
}

