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
    @State private var path = NavigationPath()
    @State private var viewingAsDeckIDs: [UUID] = []
    @State private var isLoadingFriendDecks = false

    private struct TaraweehRoute: Hashable {}

    private var viewingAsFriend: HifzworldUser? {
        guard reciteVM.isCoachingFriend else { return nil }
        return reciteVM.coachSubject
    }

    private var viewingAsLabel: String {
        guard let friend = viewingAsFriend else { return "" }
        return friend.handle.map { "@\($0)" } ?? friend.displayName
    }

    private var decksNavigationTitle: String { "Decks" }

    private var displayedDecks: [MushafBundle] {
        if viewingAsFriend != nil {
            return viewingAsDeckIDs.compactMap { bundleStore.bundle(id: $0) }
        }
        return bundleStore.bundles
    }

    private var friends: [FriendshipDTO] { friendships?.friends ?? [] }
    private var pendingIncoming: [FriendshipDTO] { friendships?.pendingIncoming ?? [] }
    private var pendingOutgoing: [FriendshipDTO] { friendships?.pendingOutgoing ?? [] }

    private var hasAnyContent: Bool {
        if viewingAsFriend != nil {
            return !displayedDecks.isEmpty || isLoadingFriendDecks
        }
        return !bundleStore.bundles.isEmpty
            || !pendingShares.isEmpty
            || !friends.isEmpty
            || !pendingIncoming.isEmpty
            || !pendingOutgoing.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewingAsFriend != nil {
                ViewingAsBanner(label: viewingAsLabel) {
                    reciteVM.exitCoachMode()
                }
            }

            NavigationStack(path: $path) {
                Group {
                    if !auth.isSignedIn {
                        SignInView(auth: auth)
                    } else if viewingAsFriend != nil {
                        viewingAsDecksContent
                    } else if !hasAnyContent {
                        emptyDecksGuide
                    } else {
                        ownDecksList
                    }
                }
                .navigationTitle(decksNavigationTitle)
                .navigationDestination(for: UUID.self) { bundleID in
                    BundleDetailView(
                        bundleID: bundleID,
                        bundleStore: bundleStore,
                        auth: auth,
                        reciteVM: reciteVM,
                        onOpenInMushaf: onOpenInMushaf
                    )
                }
                .navigationDestination(for: TaraweehRoute.self) { _ in
                    TaraweehModeView(
                        reciteVM: reciteVM,
                        auth: auth,
                        bundleStore: bundleStore
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
                    if viewingAsFriend == nil, auth.isSignedIn {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                path.append(TaraweehRoute())
                            } label: {
                                Image(systemName: "moon.stars")
                            }
                            .accessibilityLabel("Taraweeh")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if viewingAsFriend != nil {
                            Button {
                                newTitle = ""
                                newDescription = ""
                                showCreateSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(!auth.isSignedIn)
                            .accessibilityLabel("New deck")
                        } else {
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
                    }
                    if auth.isSignedIn {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(viewingAsFriend != nil ? "Refresh" : "Sync") {
                                Task {
                                    if viewingAsFriend != nil {
                                        await reloadFriendDecks()
                                    } else {
                                        await syncBundles()
                                    }
                                }
                            }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if auth.isSignedIn && !hasAnyContent && viewingAsFriend == nil {
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
                        navigationTitle: viewingAsFriend.map { "New Deck for \($0.displayName)" } ?? "New Deck",
                        onCreate: {
                            Task { await createDeck() }
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
                            Task { await pushEditedBundle(id: editingBundleID) }
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
                .task(id: viewingAsFriend?.id) {
                    path = NavigationPath()
                    await reloadFriendDecks()
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
    }

    @ViewBuilder
    private var emptyDecksGuide: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)

                VStack(spacing: 8) {
                    Text("No Decks Yet")
                        .font(.title2.bold())
                    Text("Decks are collections of Mushaf pages you save for review, share with friends, and mark while someone recites.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Add pages from the Mushaf")
                        .font(.headline)

                    Text("Open the Mushaf tab, go to a page you want to keep, then tap the stacked pages + icon in the top bar to create a deck or add that page to one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image("GuideDecksEmptyAdd")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .accessibilityLabel("Screenshot of the add-to-deck button in the Mushaf top bar")

                    Text("You can also tap + here on Decks to create an empty deck, then add pages later.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        newTitle = ""
                        newDescription = ""
                        showCreateSheet = true
                    } label: {
                        Label("New Deck", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
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

    @ViewBuilder
    private var viewingAsDecksContent: some View {
        if isLoadingFriendDecks && displayedDecks.isEmpty {
            ProgressView("Loading decks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedDecks.isEmpty {
            ContentUnavailableView(
                "No Decks Yet",
                systemImage: "square.stack.3d.up",
                description: Text("Create a deck for \(viewingAsFriend?.displayName ?? "this friend"). It will be owned by them.")
            )
        } else {
            List {
                Section("Decks") {
                    ForEach(displayedDecks) { bundle in
                        deckListRow(bundle, allowsDelete: true)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await reloadFriendDecks() }
        }
    }

    @ViewBuilder
    private var ownDecksList: some View {
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

            Section {
                ForEach(displayedDecks) { bundle in
                    deckListRow(bundle, allowsDelete: !bundle.isShared)
                }
            } header: {
                Text("My Decks")
            } footer: {
                Text("Hold a deck to edit its title and pages. Swipe left for a quick rename or delete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func deckListRow(_ bundle: MushafBundle, allowsDelete: Bool) -> some View {
        bundleRow(bundle)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    startEditing(bundle)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)

                if allowsDelete {
                    Button(role: .destructive) {
                        Task { await deleteDisplayedDeck(bundle) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bundle.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if bundle.isShared, viewingAsFriend == nil {
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
            .onTapGesture {
                openDeck(bundle)
            }
            .onLongPressGesture {
                path.append(bundle.id)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to open in Mushaf. Hold to edit title and pages.")

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

    private func openDeck(_ bundle: MushafBundle) {
        guard let page = bundle.pageNumbers.first else {
            // Empty decks can't activate — open the editor to add pages.
            path.append(bundle.id)
            return
        }
        onOpenInMushaf(bundle.id, page)
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

    private func pushEditedBundle(id: UUID) async {
        guard let bundle = bundleStore.bundle(id: id),
              bundle.serverID != nil,
              !bundle.isShared
        else { return }
        do {
            try await RemoteBundleService().updateBundle(bundle, mushafID: reciteVM.mushafID)
        } catch {
            syncError = error.localizedDescription
        }
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

    private func deleteDisplayedDeck(_ bundle: MushafBundle) async {
        await deleteBundle(bundle)
        viewingAsDeckIDs.removeAll { $0 == bundle.id }
    }

    private func createDeck() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let friend = viewingAsFriend {
            do {
                let remote = try await FriendsService().createBundle(
                    forFriendUserID: friend.id,
                    title: title,
                    description: newDescription,
                    mushafID: reciteVM.mushafID
                )
                bundleStore.upsertAcceptedShare(remote)
                if let localID = bundleStore.bundle(serverID: remote.id)?.id {
                    viewingAsDeckIDs.insert(localID, at: 0)
                }
            } catch {
                syncError = error.localizedDescription
            }
            return
        }

        _ = bundleStore.createBundle(title: title, description: newDescription)
        await syncBundles()
    }

    private func reloadFriendDecks() async {
        guard let friend = viewingAsFriend else {
            viewingAsDeckIDs = []
            isLoadingFriendDecks = false
            return
        }

        isLoadingFriendDecks = true
        defer { isLoadingFriendDecks = false }

        do {
            let response = try await FriendsService().bundles(forFriendUserID: friend.id)
            var ids: [UUID] = []
            for remote in response.bundles {
                bundleStore.upsertAcceptedShare(remote)
                if let localID = bundleStore.bundle(serverID: remote.id)?.id {
                    ids.append(localID)
                }
            }
            viewingAsDeckIDs = ids
            syncError = nil
        } catch {
            syncError = error.localizedDescription
            if viewingAsDeckIDs.isEmpty {
                viewingAsDeckIDs = []
            }
        }
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
