//
//  NewMount.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/26/25.
//

import SwiftUI

struct NewMount: View {
    @State private var model = CreateMountModel()

    // Optional callbacks so a parent can handle actions
    var onSubmit: ((String, String, String) -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("URL (e.g. smb://host:port/share)", text: $model.urlString)
                        .autocorrectionDisabled(true)
                    
                }

                Section("Credentials") {
                    TextField("User", text: $model.username)
                        .autocorrectionDisabled(true)
                    SecureField("Password", text: $model.password)
                }

                Section {
                    Button("Submit") {
                        if let onSubmit { onSubmit(model.urlString, model.username, model.password) }
                        //FIXME: wrap
                        Task{
                            try? await model.saveAll()
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.urlString.isEmpty)

                    Button("Cancel") {
                        if let onCancel { onCancel() }
                        dismiss()
                    }
                }
            }
            .navigationTitle("New Mount")
            .toolbar {
                ToolbarItem() {
                    Button("Cancel") {
                        if let onCancel { onCancel() }
                        dismiss()
                    }
                }
                ToolbarItem() {
                    Button("Submit") {
                        if let onSubmit { onSubmit(model.urlString, model.username, model.password) }
                        //FIXME: wrap
                        Task{
                            try? await model.saveAll()
                        }
                       
                        dismiss()
                    }
                    .disabled(model.urlString.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NewMount()
}
