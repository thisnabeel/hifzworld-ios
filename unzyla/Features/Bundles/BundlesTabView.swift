import SwiftUI

struct BundlesTabView: View {
    @Bindable var bundleStore: BundleStore
    @Bindable var auth: AuthService
    @Bindable var reciteVM: ReciteViewModel
    let onOpenInMushaf: (UUID, Int) -> Void
    let onStartRecording: (MushafBundle) async -> String?
    let onReviewRecording: (DeckRecording) -> Void

    @State private var showCreateSheet = false
    @State private var showEditSheet = false
    @State private var showAddFriendSheet = false
    @State private var newTitle = ""
    @State private var newDescription = ""
    @State private var editingBundleID: UUID?
    @State private var pendingShares: [BundleShareDTO] = []
    @State private var friendships: FriendshipsResponse?
    @State private var syncError: String?
    @State private var recordingsDeck: MushafBundle?
    @State private var recordingStore = DeckRecordingStore.shared
    @Bindable private var recorder = DeckAudioRecorder.shared
    @State private var recordError: String?

    private var friends: [FriendshipDTO] { friendships?.friends ?? [] }
    private var pendingIncoming: [FriendshipDTO] { friendships?.pendingIncoming ?? [] }
    private var pendingOutgoing: [FriendshipDTO] { friendships?.pendingOutgoing ?? [] }

    private var hasAnyContent: Bool {
        !bundleStore.bundles.isEmpty
            || !pendingShares.isEmpty
            || !friends.isEmpty
            || !pendingIncoming.isEmpty
            || !pendingOutgoing.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    SignInView(auth: auth)
                } else if !hasAnyContent {
                    ContentUnavailableView(
                        "No Decks Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Create a deck, add a friend by email or @handle, then view their decks to listen and mark feedback.")
                    )
                } else {
                    List {
                        Section {
                            Text("Decks are collections of Mushaf pages you save for review. Add friends to view their decks, create decks for them, and mark feedback while they recite.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        }

                        if !pendingIncoming.isEmpty {
                            Section("Friend Requests") {
                                ForEach(pendingIncoming) { friendship in
                                    friendRequestRow(friendship)
                                }
                            }
                        }

                        if !pendingOutgoing.isEmpty {
                            Section("Pending Invites") {
                                ForEach(pendingOutgoing) { friendship in
                                    HStack {
                                        friendIdentity(friendship.user)
                                        Spacer()
                                        Text("Pending")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        Section {
                            ForEach(friends) { friendship in
                                if let user = friendship.user {
                                    NavigationLink {
                                        FriendDecksView(
                                            friend: user,
                                            bundleStore: bundleStore,
                                            auth: auth,
                                            reciteVM: reciteVM,
                                            onOpenInMushaf: onOpenInMushaf
                                        )
                                    } label: {
                                        friendIdentity(user)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            Task { await removeFriendship(friendship) }
                                        } label: {
                                            Label("Remove", systemImage: "person.badge.minus")
                                        }
                                    }
                                }
                            }

                            Button {
                                showAddFriendSheet = true
                            } label: {
                                Label("Add Friend", systemImage: "person.badge.plus")
                            }
                        } header: {
                            Text("Friends")
                        } footer: {
                            Text("Open a friend to view their decks or create one for them.")
                        }

                        if !pendingShares.isEmpty {
                            Section("Incoming Shares") {
                                ForEach(pendingShares) { share in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(share.bundle?.title ?? "Shared deck")
                                            .font(.headline)
                                        Text("From \(share.sharedBy?.displayName ?? "Someone")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button("Accept") {
                                            Task { await acceptShare(share) }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Section("My Decks") {
                            ForEach(bundleStore.bundles) { bundle in
                                bundleRow(bundle)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            startEditing(bundle)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)

                                        Button(role: .destructive) {
                                            DeckRecordingStore.shared.deleteAll(for: bundle.id)
                                            bundleStore.deleteBundle(id: bundle.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: UUID.self) { bundleID in
                BundleDetailView(
                    bundleID: bundleID,
                    bundleStore: bundleStore,
                    auth: auth,
                    reciteVM: reciteVM,
                    onOpenInMushaf: onOpenInMushaf
                )
            }
            .navigationDestination(item: $recordingsDeck) { bundle in
                DeckRecordingsView(
                    deckID: bundle.id,
                    deckTitle: bundle.title,
                    onReview: { recording in
                        recordingsDeck = nil
                        onReviewRecording(recording)
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            newTitle = ""
                            newDescription = ""
                            showCreateSheet = true
                        } label: {
                            Label("New Deck", systemImage: "plus")
                        }
                        Button {
                            showAddFriendSheet = true
                        } label: {
                            Label("Add Friend", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!auth.isSignedIn)
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sync") { Task { await syncBundles() } }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if auth.isSignedIn && !hasAnyContent {
                    Button {
                        showAddFriendSheet = true
                    } label: {
                        Label("Add Friend", systemImage: "person.badge.plus")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(20)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateBundleSheet(
                    title: $newTitle,
                    description: $newDescription,
                    onCreate: {
                        _ = bundleStore.createBundle(title: newTitle, description: newDescription)
                        Task { await syncBundles() }
                    }
                )
            }
            .sheet(isPresented: $showEditSheet) {
                EditBundleSheet(
                    title: $newTitle,
                    description: $newDescription,
                    onSave: {
                        guard let editingBundleID else { return }
                        bundleStore.updateBundle(
                            id: editingBundleID,
                            title: newTitle,
                            description: newDescription
                        )
                    }
                )
            }
            .sheet(isPresented: $showAddFriendSheet) {
                AddFriendSheet {
                    Task { await refreshFriends() }
                }
            }
            .task(id: auth.isSignedIn) {
                guard auth.isSignedIn else { return }
                await refreshShares()
                await refreshFriends()
            }
            .alert("Sync Error", isPresented: Binding(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("OK") { syncError = nil }
            } message: {
                Text(syncError ?? "")
            }
            .alert("Recording Error", isPresented: Binding(
                get: { recordError != nil },
                set: { if !$0 { recordError = nil } }
            )) {
                Button("OK") { recordError = nil }
            } message: {
                Text(recordError ?? "")
            }
        }
    }

    @ViewBuilder
    private func friendIdentity(_ user: HifzworldUser?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user?.displayName ?? "Friend")
                .font(.headline)
            if let handle = user?.handle, !handle.isEmpty {
                Text("@\(handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let email = user?.email, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func friendRequestRow(_ friendship: FriendshipDTO) -> some View {
        HStack {
            friendIdentity(friendship.user)
            Spacer()
            Button("Accept") {
                Task { await acceptFriendship(friendship) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button("Decline", role: .destructive) {
                Task { await removeFriendship(friendship) }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func bundleRow(_ bundle: MushafBundle) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                NavigationLink(value: bundle.id) {
                    EmptyView()
                }
                .opacity(0)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(bundle.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if bundle.isShared {
                            Text("Shared")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    if !bundle.description.isEmpty {
                        Text(bundle.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text("\(bundle.pageNumbers.count) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            let hasRecordings = recordingStore.count(for: bundle.id) > 0
            let isThisRecording = recorder.isRecording && recorder.activeDeckID == bundle.id

            HStack(spacing: 8) {
                if hasRecordings {
                    Button {
                        recordingsDeck = bundle
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accent.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Previous recordings for \(bundle.title)")
                }

                Button {
                    Task { await startRecording(for: bundle) }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isThisRecording ? .white : AppTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(isThisRecording ? Color.red : AppTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(recorder.isRecording && !isThisRecording)
                .accessibilityLabel(isThisRecording ? "Recording \(bundle.title)" : "Record \(bundle.title)")
            }
        }
    }

    private func startRecording(for bundle: MushafBundle) async {
        if recorder.isRecording, recorder.activeDeckID == bundle.id {
            return
        }
        if let error = await onStartRecording(bundle) {
            recordError = error
        }
    }

    private func startEditing(_ bundle: MushafBundle) {
        editingBundleID = bundle.id
        newTitle = bundle.title
        newDescription = bundle.description
        showEditSheet = true
    }

    private func syncBundles() async {
        let service = RemoteBundleService()
        do {
            try await service.uploadLocalBundles(from: bundleStore, mushafID: reciteVM.mushafID)
            try await service.sync(into: bundleStore, mushafID: reciteVM.mushafID)
            await refreshFriends()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func refreshShares() async {
        do {
            pendingShares = try await RemoteBundleService().pendingShares()
        } catch {
            pendingShares = []
        }
    }

    private func refreshFriends() async {
        do {
            friendships = try await FriendsService().list()
        } catch {
            // Keep prior list if refresh fails.
        }
    }

    private func acceptFriendship(_ friendship: FriendshipDTO) async {
        do {
            _ = try await FriendsService().accept(id: friendship.id)
            await refreshFriends()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func removeFriendship(_ friendship: FriendshipDTO) async {
        do {
            try await FriendsService().remove(id: friendship.id)
            await refreshFriends()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func deleteBundle(_ bundle: MushafBundle) async {
        if let serverID = bundle.serverID, !bundle.isShared {
            do {
                try await RemoteBundleService().deleteBundle(serverID: serverID)
            } catch {
                syncError = error.localizedDescription
                return
            }
        }
        DeckRecordingStore.shared.deleteAll(for: bundle.id)
        bundleStore.deleteBundle(id: bundle.id)
    }

    private func acceptShare(_ share: BundleShareDTO) async {
        do {
            let accepted = try await RemoteBundleService().acceptShare(id: share.id)
            if let remote = accepted.bundle {
                bundleStore.upsertAcceptedShare(remote)
            }
            await refreshShares()
            await syncBundles()
        } catch {
            syncError = error.localizedDescription
        }
    }
}
