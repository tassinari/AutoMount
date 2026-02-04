//
//  NewMount.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/26/25.
//

import SwiftUI

struct AddEditMount: View {
    @State var model : AddEditModel

    // Optional callbacks so a parent can handle actions
    var onSubmit: ((String, String, String) -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
       
        VStack{
            HStack{
                Text("New Connection")
                    .font(.title)
                Spacer()
            }
            Form {
                Section() {
                    TextField("URL", text: $model.urlString, prompt: Text("smb://host:port/share"))
                        .autocorrectionDisabled(true)
                    TextField("Location", text: $model.urlString, prompt: Text("/Volumes/share"))
                        .autocorrectionDisabled(true)
                    Text("Optional, leave blank to default to standard /Volumes/share")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Username", text: $model.username)
                        .autocorrectionDisabled(true)
                    SecureField("Password", text: $model.password)
                } header: {
                    HStack {
                        Toggle("Use Credentials", isOn: Binding<Bool>.constant(true))
                    }
                    .padding([.top, .bottom], 8)
                }


                Section {
                    HStack {
                        Toggle("Auto mount", isOn: Binding<Bool>.constant(true))
                        Spacer()
                        Button("Cancel") {
                            if let onCancel { onCancel() }
                            dismiss()
                        }
                        
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
                    }
                }
                
          
        }
        }
            .padding()
    }
}

#Preview {
    NavigationStack{
        AddEditMount(model: AddEditModel(store: MockStore.store))
    }
    
}
