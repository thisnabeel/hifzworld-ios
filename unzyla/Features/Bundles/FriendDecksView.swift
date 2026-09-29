import SwiftUI

/// Browse and manage a friend's decks while acting as their coach.
struct FriendDecksView: View {
    let friend: HifzworldUser
    @Bindable var bundleStore: BundleStore
    @Bindable var auth: AuthService
    @Bindable var reciteVM: ReciteViewModel
    let onOpenInMushaf: (UUID, Int) -> Void
    /// When true, this is the Decks tab root while “Marking for” that friend.
    var isViewingAsRoot: Bool = false

    @State private var bundles: [RemoteMushafBundle] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var newTitle = ""
    @State private var newDescription = ""

    private var friendLabel: String {
        friend.handle.map { "@\($0)" } ?? friend.displayName
    }

    var body: some View {
        Group {
            if isLoading && bundles.isEmpty {
                ProgressView("Loading decks…")
            } else if let errorMessage, bundles.isEmpty {
                ContentUnavailableView(
                    "Couldn’t Load Decks",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if bundles.isEmpty {
                ContentUnavailableView(
                    "No Decks Yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create a deck for \(friend.displayName). It will be owned by them, and you can listen and mark feedback.")
                )
            } else {
                List {
                    Section {
                        Text(introCopy)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Color.clear)
                    }

                    Section("\(friend.displayName)’s Decks") {
                        ForEach(bundles) { remote in
                            if let localID = localID(for: remote) {
                                NavigationLink {
                                    BundleDetailView(
                                        bundleID: localID,
                                        bundleStore: bundleStore,
                                        auth: auth,
                                        reciteVM: reciteVM,
                                        onOpenInMushaf: onOpenInMushaf
                                    )
                                } label: {
                                    friendDeckLabel(remote)
                                }
                            } else {
                                Button {
                                    _ = ensureLocal(remote)
                                } label: {
                                    friendDeckLabel(remote)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(friendLabel)
        .navigationBarTitleDisplayMode(isViewingAsRoot ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newTitle = ""
                    newDescription = ""
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New deck for \(friend.displayName)")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateBundleSheet(
                title: $newTitle,
                description: $newDescription,
                navigationTitle: "New Deck for \(friend.displayName)",
                onCreate: {
                    Task { await createDeck() }
                }
            )
        }
        .task(id: friend.id) {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil && !bundles.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var introCopy: String {
        if isViewingAsRoot {
            return "Marking for \(friendLabel). Showing their decks — open one to review together, or create a new deck for them."
        }
        return "Viewing as \(friend.displayName). Decks are owned by them — you can open, edit pages, and join review as their listener."
    }

    @ViewBuilder
    private func friendDeckLabel(_ remote: RemoteMushafBundle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(remote.title)
                .font(.headline)
                .foregroundStyle(.primary)
            if !remote.description.isEmpty {
                Text(remote.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(remote.pageNumbers.count) pages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func localID(for remote: RemoteMushafBundle) -> UUID? {
        bundleStore.bundle(serverID: remote.id)?.id
    }

    @discardableResult
    private func ensureLocal(_ remote: RemoteMushafBundle) -> UUID? {
        bundleStore.upsertAcceptedShare(remote)
        return bundleStore.bundle(serverID: remote.id)?.id
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await FriendsService().bundles(forFriendUserID: friend.id)
            for remote in response.bundles {
                bundleStore.upsertAcceptedShare(remote)
            }
            bundles = response.bundles
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createDeck() async {
        do {
            let remote = try await FriendsService().createBundle(
                forFriendUserID: friend.id,
                title: newTitle,
                description: newDescription,
                mushafID: reciteVM.mushafID
            )
            bundleStore.upsertAcceptedShare(remote)
            bundles.insert(remote, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
