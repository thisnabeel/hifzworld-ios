import SwiftUI

struct PickFriendSheet: View {
    let onSelect: (HifzworldUser) -> Void

    @State private var friendships: FriendshipsResponse?
    @State private var query = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var friends: [HifzworldUser] {
        (friendships?.friends ?? []).compactMap(\.user)
    }

    private var filteredFriends: [HifzworldUser] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return friends }
        return friends.filter { user in
            user.displayName.lowercased().contains(q)
                || (user.handle?.lowercased().contains(q) ?? false)
                || (user.email?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search friends or enter email / @handle", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                } footer: {
                    Text("Your own Mushaf is the default. Pick a friend only when you want to mark theirs.")
                }

                Section("Friends") {
                    if isLoading {
                        ProgressView()
                    } else if filteredFriends.isEmpty {
                        Text(friends.isEmpty ? "No accepted friends yet. Add someone by email or @handle below." : "No matches.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredFriends) { user in
                            friendRow(user, subtitle: user.handle.map { "@\($0)" } ?? user.email)
                        }
                    }
                }

                if canSubmitLookup {
                    Section {
                        Button {
                            Task { await addOrSelectFromQuery() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Use \(trimmedQuery)")
                            }
                        }
                        .disabled(isSubmitting)
                    } footer: {
                        Text("They must already be an accepted friend. If not, send a friend request from Decks first.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mark for Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitLookup: Bool {
        let q = trimmedQuery
        return !q.isEmpty && filteredFriends.isEmpty
    }

    @ViewBuilder
    private func friendRow(_ user: HifzworldUser, subtitle: String?) -> some View {
        Button {
            onSelect(user)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friendships = try await FriendsService().list()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addOrSelectFromQuery() async {
        let value = trimmedQuery
        guard !value.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Prefer matching an already-loaded friend.
        if let match = friends.first(where: {
            $0.email?.lowercased() == value.lowercased()
                || $0.handle?.lowercased() == value.lowercased().deletePrefix("@")
                || "@\($0.handle ?? "")".lowercased() == value.lowercased()
        }) {
            onSelect(match)
            dismiss()
            return
        }

        // Try adding — if already friends, API may return existing; then refresh and select.
        let email: String?
        let handle: String?
        if value.contains("@"), !value.hasPrefix("@") {
            email = value
            handle = nil
        } else {
            email = nil
            handle = value.deletePrefix("@")
        }

        do {
            let friendship = try await FriendsService().add(email: email, handle: handle)
            await reload()
            if friendship.status == "accepted", let user = friendship.user {
                onSelect(user)
                dismiss()
            } else {
                errorMessage = "Friend request sent. They must accept before you can mark their Mushaf."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    func deletePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
