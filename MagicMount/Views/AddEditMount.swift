//
//  NewMount.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/26/25.
//

import SwiftUI

struct AddEditMount: View {
    @State var model : AddEditModel
    @Binding var errorMessage: String?

    // Optional callbacks so a parent can handle actions
    var onSubmit: ((String) -> Void)? = nil
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
                Section {
                    ServerComboBox(text: $model.urlString, items: model.previousServers) {
                        guard !model.urlString.isEmpty else { return }
                        if let onSubmit { onSubmit(model.urlString) }
                        Task {
                            do {
                                try await model.saveAll()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            dismiss()
                        }
                    }
                    .padding()

                    
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
                            Task {
                                do {
                                    try await model.saveAll()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                dismiss()
                            }
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
        AddEditMount(model: AddEditModel(store: MockStore.store), errorMessage: .constant(nil))
    }
    .frame(width: 500, height: 400)
    
}

