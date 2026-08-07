//
//  NewMount.swift
//  AutoMount
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
                Text("add_edit.title")
                    .font(.title)
                Spacer()
            }
            HStack {
                Text("add_edit.keychain_info")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding([.top, .bottom], 8)
                Spacer()
            }
            if isConnecting {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Text("add_edit.status.connecting")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer()
                HStack {
                    Spacer()
                    Button(String(localized: "common.button.cancel")) {
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
                            Toggle("add_edit.toggle.always_mounted", isOn: $model.manage)
                            Spacer()
                            Button(String(localized: "common.button.cancel")) {
                                if let onCancel { onCancel() }
                                dismiss()
                            }

                            Button(String(localized: "add_edit.button.submit")) {
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
