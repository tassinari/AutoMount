import Foundation
import SwiftUI
import libMounter

enum CreateMountState{
    case create, edit
}

enum AddEditModelError : Swift.Error {
    case missingValues, badURL
}
@MainActor @Observable final class AddEditModel {
   
    var urlString: String
    private let store : ShareDataModel
    var location: String

    init(urlString: String = "",store: ShareDataModel) {
        self.store = store
        self.urlString = urlString
        self.location = ""
    }

    func clear() {
        urlString = ""
        location = ""
    }
   
    func saveAll() async throws {
      
        guard let url = URL(string: urlString) else { throw AddEditModelError.badURL }
        let mount = Share( url: url, name: "media", mountPoint: nil,managed: true, connected: .unmounted)
        
        let resp = try await store.mount(mount, ui: true)
        switch resp {
        case .success:
            print("success")
        default:
            print("got \(resp)")
        }
//        try await Task {
//            //try await store.manage(mount)
//        }.value
    }
}

