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
    var onSubmit: ((String) -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var useCustomLocation: Bool = false

    var body: some View {
       
        VStack{
            HStack{
                Text("New Connection")
                    .font(.title)
                Spacer()
            }
            Form {
                Section {
                    ServerComboBox(text: $model.urlString, items: model.previousServers)
                        .padding()

                    Toggle("Mount to custom location", isOn: $useCustomLocation)

                    if useCustomLocation {
                        TextField("Location", text: $model.location, prompt: Text("/Volumes/share"))
                            // .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding()
                       
                    }
                }
                Section {
                    HStack {
                        Toggle("Always keep mounted", isOn: $model.manage)
                        Spacer()
                        Button("Cancel") {
                            if let onCancel { onCancel() }
                            dismiss()
                        }
                        
                        Button("Submit") {
                            if let onSubmit { onSubmit(model.urlString) }
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
    .frame(width: 500, height: 400)
    
}

