import SwiftUI
import UIKit

struct ShareBundleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didCopy = false

    let bundleTitle: String
    let createInviteLink: () async throws -> URL

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck") {
                    Text(bundleTitle)
                }

                Section {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Creating share link…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let inviteURL {
                        Text(inviteURL.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        ShareLink(item: inviteURL, subject: Text(bundleTitle), message: Text("Join my deck on Hifz.World")) {
                            Label("Share via Messages, WhatsApp…", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            UIPasteboard.general.string = inviteURL.absoluteString
                            didCopy = true
                        } label: {
                            Label(didCopy ? "Copied" : "Copy Link", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        }
                    }
                } footer: {
                    Text("Anyone with the link can open it in Hifz.World and join this deck after signing in.")
                }
            }
            .navigationTitle("Share Deck")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
            .task { await loadInvite() }
        }
    }

    private func loadInvite() async {
        isLoading = true
        defer { isLoading = false }
        do {
            inviteURL = try await createInviteLink()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
