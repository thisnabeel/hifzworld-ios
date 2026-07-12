import SwiftUI

struct ShareBundleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isSharing = false
    @State private var errorMessage: String?

    let bundleTitle: String
    let onShare: (String) async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Bundle") {
                    Text(bundleTitle)
                }
                Section("Recipient") {
                    TextField("Email address", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
            }
            .navigationTitle("Share Bundle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { Task { await share() } }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSharing)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func share() async {
        isSharing = true
        defer { isSharing = false }
        do {
            try await onShare(email.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
