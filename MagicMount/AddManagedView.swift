//
//  AddManagedView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/29/25.
//
import SwiftUI

struct AddManagedView: View {
    @State var share: Share
    @State private var storeInKeychain: Bool = true
    @State private var username: String = ""
    @State private var password: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {

            Form {
                Section {
                    
                    Text("Auto manage \"\(share.name)\"?")
                        .font(.title)
                    Text("Magic mount will ensure its connected on wake/sleep and network changes.")
                        .font(.caption)

                    Toggle("In Keychain", isOn: $storeInKeychain)

                    
                    TextField("Username", text: $username)
                        .disabled(storeInKeychain)
                        .foregroundStyle(storeInKeychain ?  .gray.opacity(0.5) : .black)
                    SecureField("Password", text: $password)
                        .disabled(storeInKeychain)
                        .foregroundStyle(storeInKeychain ?  .gray.opacity(0.5) : .black)
                    
                    
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                   dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    do{
                        try StorageManager().addMount(share)
                        dismiss()
                    }catch{
                        //FIXME: Logger
                    }
                    
                   
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }
}

#Preview {
    AddManagedView(share: Share(user: "", password: "", url: URL(fileURLWithPath:""), name: "Photo", mountPoint: "/some/path",connected: false))
}
