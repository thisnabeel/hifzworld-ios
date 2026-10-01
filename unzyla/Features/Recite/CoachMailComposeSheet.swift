import SwiftUI

struct CoachMailComposeSheet: View {
    let recipient: HifzworldUser
    let currentPage: Int
    let mushafID: Int

    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""
    @State private var pageNumbers: [Int] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var recipientLabel: String {
        if let handle = recipient.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return recipient.displayName
    }

    private var canSend: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 1 && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipientLabel)
                        .foregroundStyle(.primary)
                } header: {
                    Text("To")
                }

                Section {
                    TextField("Write a note…", text: $bodyText, axis: .vertical)
                        .lineLimit(5...14)
                } header: {
                    Text("Message")
                }

                Section {
                    if pageNumbers.isEmpty {
                        Text("No pages attached yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pageNumbers, id: \.self) { page in
                                    pageChip(page, removable: true)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Button {
                        addCurrentPage()
                    } label: {
                        Label("Add page \(PrintedPage.display(currentPage))", systemImage: "plus.circle.fill")
                    }
                    .disabled(pageNumbers.contains(currentPage))
                } header: {
                    Text("Pages")
                } footer: {
                    Text("They can tap a page in the message to open it in the Mushaf.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send Mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(!canSend)
                }
            }
            .overlay {
                if isSending {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Sent", isPresented: $didSucceed) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your note was sent to \(recipientLabel).")
            }
        }
    }

    private func pageChip(_ page: Int, removable: Bool) -> some View {
        HStack(spacing: 6) {
            Text("p. \(PrintedPage.display(page))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if removable {
                Button {
                    pageNumbers.removeAll { $0 == page }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.18)))
    }

    private func addCurrentPage() {
        guard currentPage > 0, !pageNumbers.contains(currentPage) else { return }
        pageNumbers.append(currentPage)
        pageNumbers.sort()
    }

    private func send() async {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await MessagesService().create(
                recipientID: recipient.id,
                body: trimmed,
                pageNumbers: pageNumbers,
                mushafID: mushafID
            )
            didSucceed = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
