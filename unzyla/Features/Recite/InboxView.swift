import SwiftUI

struct InboxView: View {
    var onOpenPage: ((Int, Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [MessageDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMessage: MessageDTO?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && messages.isEmpty {
                    ProgressView("Loading inbox…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    emptyInboxGuide
                } else {
                    List(messages) { message in
                        Button {
                            selectedMessage = message
                        } label: {
                            inboxRow(message)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .navigationDestination(item: $selectedMessage) { message in
                MessageDetailView(
                    message: message,
                    onOpenPage: onOpenPage,
                    onMarkedRead: { updated in
                        if let index = messages.firstIndex(where: { $0.id == updated.id }) {
                            messages[index] = updated
                        }
                        selectedMessage = updated
                    }
                )
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

    private var emptyInboxGuide: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "envelope")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)

                VStack(spacing: 8) {
                    Text("No Mail Yet")
                        .font(.title2.bold())
                    Text("Notes from friends who mark for you will show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Become friends first")
                        .font(.headline)

                    Text("On the Mushaf, tap the person + icon next to the menu. Pick a friend so you can mark for each other and send notes to this inbox.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image("GuideInboxAddFriend")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .accessibilityLabel("Screenshot of the add-friend button in the Mushaf top bar")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func inboxRow(_ message: MessageDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.isUnread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderLabel)
                        .font(.subheadline.weight(message.isUnread ? .semibold : .medium))
                    Spacer()
                    if let createdAt = message.createdAt {
                        Text(createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !message.pageNumbers.isEmpty {
                    Text(message.pageNumbers.map { "p. \($0)" }.joined(separator: " · "))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            messages = try await MessagesService().list()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct MessageDetailView: View {
    let message: MessageDTO
    var onOpenPage: ((Int, Int) -> Void)?
    var onMarkedRead: ((MessageDTO) -> Void)?

    @State private var current: MessageDTO
    @State private var errorMessage: String?

    init(
        message: MessageDTO,
        onOpenPage: ((Int, Int) -> Void)? = nil,
        onMarkedRead: ((MessageDTO) -> Void)? = nil
    ) {
        self.message = message
        self.onOpenPage = onOpenPage
        self.onMarkedRead = onMarkedRead
        _current = State(initialValue: message)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From \(current.senderLabel)")
                        .font(.headline)
                    if let createdAt = current.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(current.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !current.pageNumbers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pages")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        FlowPageChips(pages: current.pageNumbers) { page in
                            onOpenPage?(page, current.mushafID)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .navigationTitle("Mail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await markReadIfNeeded()
        }
    }

    private func markReadIfNeeded() async {
        guard current.isUnread else { return }
        do {
            let updated = try await MessagesService().markRead(id: current.id)
            current = updated
            onMarkedRead?(updated)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct FlowPageChips: View {
    let pages: [Int]
    let onTap: (Int) -> Void

    var body: some View {
        FlexiblePageChipWrap(pages: pages, onTap: onTap)
    }
}

private struct FlexiblePageChipWrap: View {
    let pages: [Int]
    let onTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { page in
                        Button {
                            onTap(page)
                        } label: {
                            Text("p. \(page)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.18))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Simple wrap: 4 chips per row.
    private var rows: [[Int]] {
        stride(from: 0, to: pages.count, by: 4).map { start in
            Array(pages[start..<min(start + 4, pages.count)])
        }
    }
}
