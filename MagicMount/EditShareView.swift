//
//  EditShareView.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/11/26.
//

import SwiftUI
import libMounter

struct EditShareView: View {
    @State var share: Share
    @Environment(\.dismiss) var dismiss

    @State private var showStopManagingConfirm = false

    var body: some View {
        VStack(spacing: 0) {

            Form {
                Section {
                    Text("Edit \(share.name)")
                        .font(.title)

                    Text("Magic Mount will ensure it’s connected on wake/sleep and network changes.")
                        .font(.caption)
                }
            }
            .padding()

            Divider()

            HStack {
                Button("Stop Managing", role: .destructive) {
                    showStopManagingConfirm = true
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Done") {
                    do {
                        try StorageManager().addMount(share)
                        dismiss()
                    } catch {
                        // FIXME: Logger
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .confirmationDialog(
            "Stop managing this share?",
            isPresented: $showStopManagingConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop Managing", role: .destructive) {
                Task{
                    do {
                        try  StorageManager().deleteMount(share)
                        dismiss()
                    }catch{
                        MagicMount.error(String(describing: error))
                    }
                }
                
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Magic Mount will no longer automatically mount this share.")
        }
    }
}

#Preview {
    EditShareView(share: Share(user: "", password: "", url: URL(fileURLWithPath:""), name: "Photo", mountPoint: "/some/path", managed: true,connected: .unmounted))
}
