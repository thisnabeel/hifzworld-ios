import SwiftUI

struct RootTabView: View {
    @State private var reciteVM = ReciteViewModel()
    @State private var bundleStore = BundleStore.shared
    @State private var auth = AuthService.shared
    @State private var selectedTab = 0
    @State private var showCreateBundleFromMushaf = false
    @State private var newBundleTitle = ""
    @State private var newBundleDescription = ""
    @Bindable private var network = NetworkMonitor.shared
    @State private var recorder = DeckAudioRecorder.shared
    @Bindable private var reviewPlayer = DeckRecordingPlayer.shared
    @State private var showMushafOnboarding = PreferencesStore.shared.needsMushafOnboarding
    @Bindable private var inviteHandler = DeckInviteHandler.shared

    var body: some View {
        Group {
            if let wall = reciteVM.iosUpdateWall, wall.blocked {
                UpdateRequiredView(
                    installed: wall.installed ?? "?",
                    required: wall.minVersion ?? "?",
                    appStoreId: wall.appStoreId
                )
            } else {
                VStack(spacing: 0) {
                    OfflineBanner(isConnected: network.isConnected)
                    ZStack(alignment: .bottomTrailing) {
                        TabView(selection: $selectedTab) {
                            ReciteTabView(
                                viewModel: reciteVM,
                                bundleStore: bundleStore,
                                selectedTab: $selectedTab,
                                onCreateBundle: {
                                    newBundleTitle = ""
                                    newBundleDescription = ""
                                    showCreateBundleFromMushaf = true
                                }
                            )
                            .tabItem {
                                Label("Mushaf", systemImage: "book.fill")
                            }
                            .tag(0)

                            BundlesTabView(
                                bundleStore: bundleStore,
                                auth: auth,
                                reciteVM: reciteVM,
                                onOpenInMushaf: openBundleInMushaf,
                                onStartRecording: startDeckRecording,
                                onReviewRecording: reviewDeckRecording
                            )
                            .tabItem {
                                Label("Decks", systemImage: "square.stack.3d.up")
                            }
                            .tag(1)

                            FeedbackTabView(auth: auth, onOpenSession: openFeedbackSession)
                                .tabItem {
                                    Label("Feedback", systemImage: "text.badge.checkmark")
                                }
                                .tag(2)
                        }
                        .background(TabBarBundlesHighlight(isActive: reciteVM.isBundleMushafMode, selectedTab: selectedTab, bundlesTabIndex: 1))
                        // On Mushaf, playback chrome lives under the deck page bar.
                        // Elsewhere, keep a global mini player above the tab bar.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if reviewPlayer.isActive,
                               !recorder.isRecording,
                               selectedTab != 0 {
                                DeckRecordingMiniPlayer(player: reviewPlayer)
                            }
                        }

                        if recorder.isRecording {
                            recordingStopControl
                                .padding(.trailing, 16)
                                // Sit just above the tab bar (same clearance the old overlay used).
                                .padding(.bottom, 58)
                        }
                    }
                }
                .fullScreenCover(isPresented: $showMushafOnboarding) {
                    MushafOnboardingView { mushafID in
                        await finishMushafOnboarding(mushafID)
                    }
                }
            }
        }
        .task {
            await auth.bootstrap()
            await reciteVM.bootstrap()
            await syncBundlesIfNeeded()
            await claimInviteIfNeeded()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await claimInviteIfNeeded() }
        }
        .onChange(of: inviteHandler.pendingToken) { _, token in
            guard token != nil else { return }
            selectedTab = 1
            Task { await claimInviteIfNeeded() }
        }
        .alert("Deck Invite", isPresented: Binding(
            get: { inviteHandler.statusMessage != nil },
            set: { if !$0 { inviteHandler.statusMessage = nil } }
        )) {
            Button("OK") { inviteHandler.statusMessage = nil }
        } message: {
            Text(inviteHandler.statusMessage ?? "")
        }
        .alert("Invite Error", isPresented: Binding(
            get: { inviteHandler.errorMessage != nil },
            set: { if !$0 { inviteHandler.errorMessage = nil } }
        )) {
            Button("OK") { inviteHandler.errorMessage = nil }
        } message: {
            Text(inviteHandler.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await reciteVM.checkMinVersion() }
        }
        .sheet(isPresented: $showCreateBundleFromMushaf) {
            CreateBundleSheet(
                title: $newBundleTitle,
                description: $newBundleDescription,
                onCreate: {
                    let bundle = bundleStore.createBundle(
                        title: newBundleTitle,
                        description: newBundleDescription
                    )
                    bundleStore.addPage(reciteVM.currentPage, to: bundle.id)
                }
            )
        }
    }

    private var recordingStopControl: some View {
        Button {
            stopDeckRecording()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 8, height: 8)
                Text(formatDuration(recorder.elapsed))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.red)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
    }

    private func finishMushafOnboarding(_ mushafID: Int) async {
        PreferencesStore.shared.chooseMushaf(mushafID)
        if reciteVM.mushafID != mushafID {
            await reciteVM.setMushafID(mushafID)
        }
        showMushafOnboarding = false
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startDeckRecording(_ bundle: MushafBundle) async -> String? {
        reviewPlayer.stop()
        guard !bundle.pageNumbers.isEmpty else {
            return "Add pages to this deck before recording."
        }
        let started = await recorder.start(deckID: bundle.id, deckTitle: bundle.title)
        guard started else {
            return recorder.lastError ?? "Could not start recording."
        }
        reciteVM.beginDeckRecordingSession(bundle: bundle)
        selectedTab = 0
        return nil
    }

    private func stopDeckRecording() {
        let marks = reciteVM.endDeckRecordingSession()
        guard var recording = recorder.stop() else { return }
        recording.marks = DeckRecording.encodeMarks(marks)
        DeckRecordingStore.shared.save(recording)
    }

    private func openBundleInMushaf(bundleID: UUID, page: Int) {
        guard !recorder.isRecording else { return }
        guard let bundle = bundleStore.bundle(id: bundleID) else { return }
        reciteVM.enterBundleMushaf(bundle: bundle, startingPage: page)
        selectedTab = 0
    }

    private func reviewDeckRecording(_ recording: DeckRecording) {
        guard !recorder.isRecording else { return }
        guard let bundle = bundleStore.bundle(id: recording.deckID) else { return }
        // Activate deck + marks first, then play, then switch tabs so Mushaf
        // observes an already-active player when it appears.
        reciteVM.reviewDeckRecording(recording, bundle: bundle)
        reviewPlayer.play(recording: recording)
        selectedTab = 0
    }

    private func openFeedbackSession(_ session: FeedbackSessionDTO) {
        guard !recorder.isRecording else { return }
        Task {
            let bundle: MushafBundle?
            #if DEBUG
            if session.id == FeedbackSessionDTO.stubPreviewID {
                bundle = bundleStore.upsertPreviewDeck(
                    serverID: FeedbackSessionDTO.stubBundleServerID,
                    title: session.bundleTitle,
                    pageNumbers: [42, 49],
                    mushafID: reciteVM.mushafID
                )
            } else {
                bundle = bundleStore.bundle(serverID: session.mushafBundleID)
            }
            #else
            bundle = bundleStore.bundle(serverID: session.mushafBundleID)
            #endif

            guard let bundle, !bundle.pageNumbers.isEmpty else { return }
            // Switch to Mushaf first so the new deck mounts on a visible tab.
            selectedTab = 0
            await reciteVM.reviewFeedbackSession(session, bundle: bundle)
        }
    }

    private func syncBundlesIfNeeded() async {
        guard auth.isSignedIn else { return }
        let service = RemoteBundleService()
        do {
            try await service.uploadLocalBundles(from: bundleStore, mushafID: reciteVM.mushafID)
            try await service.sync(into: bundleStore, mushafID: reciteVM.mushafID)
        } catch {
            // Non-fatal during bootstrap
        }
    }

    private func claimInviteIfNeeded() async {
        await inviteHandler.claimIfNeeded(
            auth: auth,
            bundleStore: bundleStore,
            mushafID: reciteVM.mushafID
        ) {
            selectedTab = 1
        }
    }
}
