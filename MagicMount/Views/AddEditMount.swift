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
    @State private var isConnecting = false
    @State private var connectTask: Task<Void, Never>?

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
            HStack {
                Text("You must save your credentials in the macOS keychain in order for SMB shares to auto mount.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding([.top, .bottom], 8)
                Spacer()
            }
            if isConnecting {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Text("Connecting...")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel") {
                        connectTask?.cancel()
                        dismiss()
                    }
                }
            } else {
                Form {
                    Section {
                        ServerComboBox(text: $model.urlString, items: model.previousServers) {
                            submitAction()
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
                                submitAction()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.urlString.isEmpty)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func submitAction() {
        guard !model.urlString.isEmpty else { return }
        if let onSubmit { onSubmit(model.urlString) }
        isConnecting = true
        connectTask = Task {
            do {
                try await model.saveAll()
            } catch is CancellationError {
                // cancelled — already dismissed by cancel button
            } catch {
                isConnecting = false
                errorMessage = error.localizedDescription
            }
            dismiss()
        }
    }
}

#Preview {
    NavigationStack{
        AddEditMount(model: AddEditModel(store: MockStore.store), errorMessage: .constant(nil))
    }
    .frame(width: 500, height: 400)

}
