import SwiftUI

struct ReciteTabView: View {
    @Bindable var viewModel: ReciteViewModel
    @Bindable var bundleStore: BundleStore
    @Binding var selectedTab: Int
    let onCreateBundle: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var goPageField = ""
    @State private var activeWordScreenFrame: CGRect?
    @State private var versePanelTopY: CGFloat?
    @State private var showAppFeedbackSheet = false
    @State private var showEditHandleSheet = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showPickFriendSheet = false
    @State private var showCoachMailSheet = false
    @State private var showInboxSheet = false
    @State private var showGuideSheet = false
    @State private var unreadMailCount = 0
    @State private var markAppearanceRevision = 0
    @State private var pagePendingDeleteFromDeck: Int?
    @Bindable private var reviewPlayer = DeckRecordingPlayer.shared
    @Bindable private var auth = AuthService.shared
    @Bindable private var bookmarkStore = MushafBookmarkStore.shared

    private var showsSpread: Bool {
        verticalSizeClass == .compact
    }

    private var showingVerseOverlay: Bool {
        !viewModel.isPaintMode && viewModel.selectedVerse != nil
    }

    private var hasPaintOnVisiblePages: Bool {
        viewModel.hasPaintedWordsOnVisiblePages
    }

    /// Full paint options when actively painting, visible pages have paints, or reviewing feedback.
    private var shouldShowPaintTools: Bool {
        viewModel.isPaintMode || hasPaintOnVisiblePages || viewModel.isViewingFeedbackMarks
    }

    private var hasViewableMarks: Bool {
        hasPaintOnVisiblePages || viewModel.hasFeedbackMarksOnVisiblePages || viewModel.isViewingFeedbackMarks
    }

    /// Audio bar replaces paint tools whenever a recording is active on Mushaf.
    /// Keep this broad to avoid device-specific timing races between
    /// deck session activation and player state updates.
    private var showsRecordingPlaybackChrome: Bool {
        reviewPlayer.isActive
    }

    /// Bottom chrome: review tools, paint tools, feedback viewing tools, prompt mode, or landscape tabs.
    private var shouldShowBottomChrome: Bool {
        viewModel.isAyahPromptMode
            || viewModel.isJournalRecording
            || viewModel.isReviewListener
            || viewModel.isCoachingFriend
            || viewModel.isSelfMarking
            || shouldShowPaintTools
            || showsSpread
    }

    /// Top chrome stays dark; bottom inset follows mushaf light/dark.
    private var reciteShellBackground: Color {
        Color(red: 0.12, green: 0.12, blue: 0.13)
    }

    private var bottomBarBackground: Color {
        if showsSpread {
            return viewModel.isDarkMode
                ? Color(red: 0.14, green: 0.14, blue: 0.15)
                : Color(red: 0.97, green: 0.97, blue: 0.98)
        }
        return viewModel.isDarkMode ? AppTheme.mushafDarkBackground : .white
    }

    private var deckSegmentBarHeight: CGFloat { showsSpread ? 32 : 36 }

    private var mushafPushOffset: CGFloat {
        guard showingVerseOverlay,
              let wordFrame = activeWordScreenFrame,
              let panelTop = versePanelTopY
        else { return 0 }

        let margin: CGFloat = 14
        return max(0, wordFrame.maxY - panelTop + margin)
    }

    /// Chrome that changes available mushaf height via layout (not overlay).
    /// Included in contentStamp so UIKit-hosted pages rescale when chrome appears.
    private var mushafLayoutChromeStamp: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.isCoachingFriend)
        hasher.combine(viewModel.reviewSession != nil)
        hasher.combine(viewModel.deckEndRangeSelection != nil)
        hasher.combine(viewModel.bundleSession?.bundleID)
        hasher.combine(shouldShowBottomChrome)
        hasher.combine(showsRecordingPlaybackChrome)
        hasher.combine(showingVerseOverlay)
        hasher.combine(showsSpread)
        return hasher.finalize()
    }

    private var mushafContentStamp: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.isPaintMode)
        hasher.combine(viewModel.isAyahPromptMode)
        hasher.combine(viewModel.isJournalRecording)
        hasher.combine(viewModel.ayahPromptCueCount)
        hasher.combine(viewModel.ayahPromptRevealedWordIDs)
        hasher.combine(viewModel.coachSubject?.id)
        hasher.combine(viewModel.isMarkingMode)
        hasher.combine(viewModel.activePaintStyle)
        hasher.combine(viewModel.displayPaintedWords)
        hasher.combine(viewModel.arePaintedWordsVisible)
        hasher.combine(viewModel.isPaintInverted)
        hasher.combine(viewModel.displaySessionMarks)
        hasher.combine(viewModel.rangeHighlightPreviewIDs)
        hasher.combine(viewModel.areSessionMarksVisible)
        hasher.combine(viewModel.isSessionMarksInverted)
        hasher.combine(viewModel.isTajweedMarkingEnabled)
        hasher.combine(markAppearanceRevision)
        hasher.combine(viewModel.isViewingFeedbackMarks)
        hasher.combine(viewModel.isMarkingMode)
        hasher.combine(viewModel.isFireMode)
        hasher.combine(viewModel.sessionMarkHeatCounts)
        hasher.combine(viewModel.pageHidden)
        hasher.combine(viewModel.activeWordID)
        hasher.combine(viewModel.selectedVerse)
        hasher.combine(viewModel.verseSearchHighlight)
        hasher.combine(viewModel.verseSearchHighlightEpoch)
        hasher.combine(mushafPushOffset)
        hasher.combine(mushafLayoutChromeStamp)
        hasher.combine(viewModel.pages[viewModel.currentPage]?.id)
        if let left = viewModel.activeSpread.leftPage {
            hasher.combine(viewModel.pages[left]?.id)
        }
        return hasher.finalize()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            reciteMainColumn
            drawerOverlay
            sidebarOverlay
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isDrawerOpen)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSidebarOpen)
        .animation(.easeInOut(duration: 0.2), value: viewModel.pageHidden)
        .onAppear {
            viewModel.setPrefersSpreadLayout(showsSpread)
            Task { await refreshUnreadMailCount() }
        }
        .onChange(of: showsSpread) { _, isSpread in
            viewModel.setPrefersSpreadLayout(isSpread)
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                Task {
                    await viewModel.reloadCoachMarksForVisiblePages()
                    await refreshUnreadMailCount()
                }
            } else if !viewModel.isReviewListener, !viewModel.isViewingFeedbackMarks {
                viewModel.sessionMarks = [:]
                viewModel.sessionMarkIDs = [:]
                viewModel.sessionMarkHeatCounts = [:]
                viewModel.coachSubject = nil
                viewModel.isMarkingMode = false
                viewModel.isFireMode = false
                unreadMailCount = 0
            } else {
                unreadMailCount = 0
            }
        }
        .onChange(of: viewModel.isDrawerOpen) { _, open in
            if open {
                Task { await refreshUnreadMailCount() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshUnreadMailCount() }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isSettingsOpen },
            set: { viewModel.isSettingsOpen = $0 }
        )) {
            QiraatSettingsSheet(
                mushafID: viewModel.mushafID,
                isDarkMode: Binding(
                    get: { viewModel.isDarkMode },
                    set: { viewModel.toggleDarkMode($0) }
                ),
                translationLanguage: Binding(
                    get: { viewModel.translationLanguage },
                    set: { viewModel.setTranslationLanguage($0) }
                ),
                isTajweedMarkingEnabled: Binding(
                    get: { viewModel.isTajweedMarkingEnabled },
                    set: { viewModel.setTajweedMarkingEnabled($0) }
                ),
                onMarkAppearanceChanged: { markAppearanceRevision &+= 1 },
                onMushafChange: { id in Task { await viewModel.setMushafID(id) } }
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isGoToPageOpen },
            set: { viewModel.isGoToPageOpen = $0 }
        )) {
            GoToPageSheet(
                pageField: $goPageField,
                juzSegments: viewModel.juzSegments,
                surahSegments: viewModel.surahSegments,
                totalPages: viewModel.totalPages,
                mushafID: viewModel.mushafID,
                onGo: { viewModel.goToPage($0) },
                onGoToVerse: { page, verseKey in
                    viewModel.goToVerse(page: page, verseKey: verseKey)
                },
                onGoToSurah: { page, surah in
                    viewModel.goToSurah(page: page, surah: surah)
                }
            )
            .onAppear {
                MushafBookmarkStore.shared.reload(mushafID: viewModel.mushafID)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isAddToBundleOpen },
            set: { viewModel.isAddToBundleOpen = $0 }
        )) {
            let surahOffer = viewModel.surahSegment(containingPage: viewModel.currentPage)
            AddPageToBundleSheet(
                currentPage: viewModel.currentPage,
                surahOffer: surahOffer,
                surahTitle: surahOffer.map { viewModel.suggestedTitle(for: $0) },
                bundleStore: bundleStore,
                onCreateBundle: {
                    viewModel.beginSinglePageDeck()
                    onCreateBundle()
                },
                onAddWholeSurah: {
                    guard let segment = surahOffer else {
                        viewModel.beginSinglePageDeck()
                        onCreateBundle()
                        return
                    }
                    viewModel.beginWholeSurahDeck(from: segment)
                    onCreateBundle()
                },
                onSelectEndRange: surahOffer.map { segment in
                    {
                        viewModel.beginDeckEndRangeSelection(from: segment)
                    }
                }
            )
        }
        .sheet(isPresented: $showAppFeedbackSheet) {
            SendAppFeedbackSheet()
        }
        .sheet(isPresented: $showEditHandleSheet) {
            EditHandleSheet(auth: AuthService.shared)
        }
        .sheet(isPresented: $showPickFriendSheet) {
            PickFriendSheet { user in
                viewModel.enterCoachMode(subject: user)
            }
        }
        .sheet(isPresented: $showCoachMailSheet) {
            if let friend = viewModel.coachSubject, viewModel.isCoachingFriend {
                CoachMailComposeSheet(
                    recipient: friend,
                    currentPage: viewModel.currentPage,
                    mushafID: viewModel.mushafID
                )
            }
        }
        .sheet(isPresented: $showInboxSheet) {
            InboxView { page, mushafID in
                showInboxSheet = false
                viewModel.isDrawerOpen = false
                Task {
                    if mushafID != viewModel.mushafID {
                        await viewModel.setMushafID(mushafID)
                    }
                    viewModel.goToPage(page)
                }
            }
            .onDisappear {
                Task { await refreshUnreadMailCount() }
            }
        }
        .sheet(isPresented: $showGuideSheet) {
            AppGuideView()
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your Hifz.World account and associated data on our servers. This cannot be undone.")
        }
        .alert("Couldn’t Delete Account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK") { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .disabled(isDeletingAccount)
    }

    private var reciteMainColumn: some View {
        VStack(spacing: 0) {
            mushafTopBar
            reviewBanner
            deckEndRangeBanner
            mushafPagerStack
            // Layout sibling (not overlay) so PageView scale-to-fit sees the reduced height
            // alongside friend strip, review banner, and bottom tools.
            deckSegmentBar
        }
        .background(reciteShellBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChromeStack
        }
        .toolbar(showsSpread ? .hidden : .automatic, for: .tabBar)
        .overlay(alignment: .bottom) {
            verseOverlayChrome
        }
        .onPreferenceChange(VersePanelTopPreferenceKey.self) { topY in
            versePanelTopY = topY
        }
        .onChange(of: viewModel.selectedVerse) { _, newValue in
            if newValue == nil {
                activeWordScreenFrame = nil
                versePanelTopY = nil
            }
        }
        .onChange(of: viewModel.activeWordID) { _, _ in
            activeWordScreenFrame = nil
        }
    }

    private var mushafTopBar: some View {
        MushafTopBar(
            currentPage: viewModel.currentPage,
            pageLabel: showsSpread ? viewModel.activeSpread.displayLabel : nil,
            selectedNarratorIDs: viewModel.selectedNarratorIDs,
            parentNarrators: viewModel.parentNarrators,
            showsCoachPicker: auth.isSignedIn,
            coachLabel: viewModel.isCoachingFriend
                ? viewModel.coachSubject.map { subject in
                    subject.handle.map { "@\($0)" } ?? subject.displayName
                }
                : nil,
            unreadMailCount: unreadMailCount,
            isCurrentPageBookmarked: bookmarkStore.mushafID == viewModel.mushafID
                ? bookmarkStore.isBookmarked(viewModel.currentPage)
                : bookmarkStore.isBookmarked(viewModel.currentPage, mushafID: viewModel.mushafID),
            onMenu: { viewModel.isDrawerOpen = true },
            onCoachPick: {
                // Self is the default mark target; the sheet is only for choosing a friend.
                if !viewModel.isMarkingMode {
                    viewModel.beginSelfMarking()
                }
                showPickFriendSheet = true
            },
            onCoachMail: {
                guard viewModel.coachSubject != nil, viewModel.isCoachingFriend else { return }
                showCoachMailSheet = true
            },
            onInbox: {
                showInboxSheet = true
            },
            onExitCoach: { viewModel.exitCoachMode() },
            onSearch: {
                goPageField = String(PrintedPage.display(viewModel.currentPage, mushafID: viewModel.mushafID))
                viewModel.isGoToPageOpen = true
            },
            onAddToBundle: {
                guard !viewModel.isDeckRecordingSession else { return }
                viewModel.isAddToBundleOpen = true
            },
            onToggleBookmark: {
                if bookmarkStore.mushafID != viewModel.mushafID {
                    bookmarkStore.reload(mushafID: viewModel.mushafID)
                }
                bookmarkStore.toggle(page: viewModel.currentPage, mushafID: viewModel.mushafID)
            }
        )
    }

    @ViewBuilder
    private var reviewBanner: some View {
        if let reviewSession = viewModel.reviewSession {
            ReviewSessionBanner(
                partnerName: reviewSession.partnerName,
                role: reviewSession.role,
                isMarkingMode: viewModel.isMarkingMode,
                activeMarkType: viewModel.activeMarkType,
                pageHidden: viewModel.pageHidden,
                onToggleMarking: { viewModel.toggleMarkingMode() },
                onSelectMarkType: { viewModel.setActiveMarkType($0) },
                onTogglePageHidden: { viewModel.togglePageHidden() },
                onEnd: { Task { await viewModel.endReviewSession() } }
            )
        }
    }

    @ViewBuilder
    private var deckEndRangeBanner: some View {
        if let selection = viewModel.deckEndRangeSelection {
            DeckEndRangeBanner(
                startPage: selection.startPage,
                currentPage: viewModel.currentPage,
                surahTitle: selection.suggestedTitle,
                onCancel: { viewModel.cancelDeckEndRangeSelection() },
                onDone: {
                    viewModel.finishDeckEndRangeSelection()
                    onCreateBundle()
                }
            )
        }
    }

    private var mushafPagerStack: some View {
        ZStack {
            AppTheme.pageBackground(dark: viewModel.isDarkMode)
            if viewModel.isLoading || viewModel.isMushafSwitching {
                ProgressView(viewModel.isMushafSwitching ? "Loading mushaf…" : "Loading mushaf…")
            } else {
                RTLMushafPager(
                    currentPage: Binding(
                        get: { viewModel.currentPage },
                        set: { viewModel.onPageChanged($0) }
                    ),
                    mushafID: viewModel.mushafID,
                    mushafReloadToken: viewModel.mushafReloadToken,
                    totalPages: viewModel.totalPages,
                    allowedPages: viewModel.bundleSession?.pages,
                    isDarkMode: viewModel.isDarkMode,
                    contentStamp: mushafContentStamp,
                    // Keep paging enabled in SwiftUI — freezing mid-gesture via isPagingEnabled
                    // rebuilds the pager and cancels hold-drag. Overlay freezes the scroll view.
                    isPagingEnabled: viewModel.isReviewPagingEnabled,
                    showsSpread: showsSpread
                ) { identityPage in
                    AnyView(spreadOrPageContent(identityPage: identityPage))
                }
                .id("\(viewModel.mushafReloadToken)-\(showsSpread)")
                .overlay {
                    MushafHighlightInteractionOverlay(
                        isEnabled: viewModel.allowsRangeHighlight,
                        onRangeHighlightBegan: { word in
                            viewModel.beginRangeHighlight(from: word)
                        },
                        onRangeHighlightChanged: { word in
                            viewModel.updateRangeHighlight(to: word)
                        },
                        onRangeHighlightEnded: {
                            Task { await viewModel.commitRangeHighlight() }
                        }
                    )
                    .allowsHitTesting(false)
                }
            }

            if viewModel.isReviewActive, !viewModel.isReviewListener, viewModel.pageHidden {
                pageHiddenOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: showsSpread ? .horizontal : [])
    }

    @ViewBuilder
    private var deckSegmentBar: some View {
        if let session = viewModel.bundleSession {
            let allowsEditing = !viewModel.isReviewActive && !viewModel.isDeckRecordingSession
            BundleMushafSegmentBar(
                session: session,
                onSelect: { viewModel.goToBundlePage(at: $0) },
                onExit: {
                    if viewModel.isReviewActive {
                        Task { await viewModel.endReviewSession() }
                    } else {
                        viewModel.exitBundleMushaf()
                    }
                },
                showsExit: !viewModel.isDeckRecordingSession,
                allowsEditing: allowsEditing,
                totalPages: viewModel.totalPages,
                onExtendBefore: { firstPage in
                    extendActiveDeck(with: firstPage - 1)
                },
                onExtendAfter: { lastPage in
                    extendActiveDeck(with: lastPage + 1)
                },
                onRequestDelete: { page in
                    pagePendingDeleteFromDeck = page
                }
            )
            .frame(height: deckSegmentBarHeight)
            .background(.ultraThinMaterial)
            .alert(
                "Remove Page?",
                isPresented: Binding(
                    get: { pagePendingDeleteFromDeck != nil },
                    set: { if !$0 { pagePendingDeleteFromDeck = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    pagePendingDeleteFromDeck = nil
                }
                Button("Remove", role: .destructive) {
                    if let page = pagePendingDeleteFromDeck {
                        removePageFromActiveDeck(page)
                    }
                    pagePendingDeleteFromDeck = nil
                }
            } message: {
                if let page = pagePendingDeleteFromDeck {
                    Text("Remove page \(PrintedPage.display(page)) from \(session.title)?")
                }
            }
        }
    }

    private func extendActiveDeck(with page: Int) {
        guard let session = viewModel.bundleSession else { return }
        guard page >= 1, page <= viewModel.totalPages else { return }
        guard bundleStore.addPage(page, to: session.bundleID) else { return }
        viewModel.reloadBundleSession(from: bundleStore, preferPage: page)
    }

    private func removePageFromActiveDeck(_ page: Int) {
        guard let session = viewModel.bundleSession else { return }
        guard bundleStore.removePage(page, from: session.bundleID) else { return }
        viewModel.reloadBundleSession(from: bundleStore)
    }

    private var pageHiddenOverlay: some View {
        Color(viewModel.isDarkMode ? AppTheme.mushafDarkBackground : AppTheme.mushafBackground)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 28, weight: .medium))
                    Text("Page hidden by listener")
                        .font(.headline)
                    Text("They’ll reveal it when you’re ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(viewModel.isDarkMode ? .white : .primary)
            }
            .transition(.opacity)
    }

    private var bottomChromeStack: some View {
        VStack(spacing: 0) {
            if showsRecordingPlaybackChrome {
                DeckRecordingMiniPlayer(player: reviewPlayer)
            } else if !showingVerseOverlay {
                if shouldShowBottomChrome {
                    paintToolsChrome(selectedVerse: nil)
                } else {
                    VStack(spacing: 8) {
                        if viewModel.showsBlockPageNavigation {
                            BlockPageNavigationButtons(
                                canGoPrevious: viewModel.previousBlockPage != nil,
                                canGoNext: viewModel.nextBlockPage != nil,
                                fill: viewModel.isDarkMode ? Color.white.opacity(0.10) : .white,
                                stroke: viewModel.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14),
                                foreground: viewModel.isDarkMode ? .white : .black,
                                onPrevious: { viewModel.goToPreviousBlockPage() },
                                onNext: { viewModel.goToNextBlockPage() }
                            )
                        }
                        HStack {
                            paintModeEntryButton
                            Spacer(minLength: 0)
                            journalRecordEntryButton
                            ayahPromptEntryButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(bottomBarBackground)
        .overlay(alignment: .top) {
            if !showsRecordingPlaybackChrome, (!shouldShowBottomChrome || showingVerseOverlay) {
                Rectangle()
                    .fill(viewModel.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    .frame(height: 1 / UIScreen.main.scale)
            }
        }
    }

    @ViewBuilder
    private var verseOverlayChrome: some View {
        if showingVerseOverlay {
            paintToolsChrome(selectedVerse: viewModel.selectedVerse)
                .background(viewModel.isDarkMode ? AppTheme.mushafDarkBackground : Color.white)
                .shadow(color: .black.opacity(0.14), radius: 16, y: -6)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: VersePanelTopPreferenceKey.self,
                            value: geo.frame(in: .global).minY
                        )
                    }
                )
        }
    }

    private func paintToolsChrome(selectedVerse: SelectedVerseDetail?) -> some View {
        let _ = markAppearanceRevision
        return ReciteBottomChrome(
            isPaintMode: selectedVerse == nil ? viewModel.isPaintMode : false,
            isMarkingMode: viewModel.isMarkingMode,
            isReviewListener: viewModel.isReviewListener,
            isCoachMarking: viewModel.isCoachingFriend || viewModel.isSelfMarking,
            showsOwnMarkViewTools: viewModel.isSelfMarking,
            areSessionMarksVisible: viewModel.areSessionMarksVisible,
            isSessionMarksInverted: viewModel.isSessionMarksInverted,
            hasSessionMarks: viewModel.hasSessionMarksOnVisiblePages,
            onToggleSessionMarksVisible: { viewModel.toggleSessionMarksVisible() },
            onToggleSessionMarksInverted: { viewModel.toggleSessionMarksInverted() },
            pageHidden: viewModel.pageHidden,
            isCompactLandscape: showsSpread,
            isDarkMode: viewModel.isDarkMode,
            translationLanguage: viewModel.translationLanguage,
            showsPaintTools: !viewModel.isAyahPromptMode && (shouldShowPaintTools || viewModel.isReviewListener),
            allowsPainting: !viewModel.isViewingFeedbackMarks && !viewModel.isAyahPromptMode,
            isAyahPromptMode: viewModel.isAyahPromptMode,
            ayahPromptCueCount: viewModel.ayahPromptCueCount,
            isJournalRecording: viewModel.isJournalRecording,
            onToggleAyahPromptMode: { viewModel.toggleAyahPromptMode() },
            onToggleJournalRecording: { Task { await viewModel.toggleJournalRecording() } },
            onSelectAyahPromptCueCount: { viewModel.setAyahPromptCueCount($0) },
            selectedTab: $selectedTab,
            activeMarkType: viewModel.activeMarkType,
            orderedMarkTypes: MarkTypeAppearance.orderedTypes(),
            showsMarkTypePills: viewModel.isTajweedMarkingEnabled,
            markTypeColors: Dictionary(
                uniqueKeysWithValues: MistakeMarkType.allCases.map { ($0, MarkTypeAppearance.color(for: $0)) }
            ),
            onToggleMarkingMode: { viewModel.toggleMarkingMode() },
            onSelectMarkType: { viewModel.setActiveMarkType($0) },
            isFireMode: viewModel.isFireMode,
            onToggleFireMode: { viewModel.toggleFireMode() },
            onTogglePageHidden: { viewModel.togglePageHidden() },
            selectedVerse: selectedVerse,
            activePaintStyle: viewModel.activePaintStyle,
            arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
            isPaintInverted: viewModel.isPaintInverted,
            hasPaintedWords: hasViewableMarks,
            onTogglePaintMode: { viewModel.togglePaintMode() },
            onTogglePaintedWordsVisible: { viewModel.togglePaintedWordsVisible() },
            onSelectPaintStyle: viewModel.setActivePaintStyle,
            onTogglePaintInverted: { viewModel.togglePaintInverted() },
            onDismissVerseRef: { viewModel.clearSelectedVerseRef() },
            showsBlockPageNavigation: !viewModel.isPaintMode && !viewModel.isAyahPromptMode && viewModel.showsBlockPageNavigation,
            canGoToPreviousBlockPage: viewModel.previousBlockPage != nil,
            canGoToNextBlockPage: viewModel.nextBlockPage != nil,
            onGoToPreviousBlockPage: { viewModel.goToPreviousBlockPage() },
            onGoToNextBlockPage: { viewModel.goToNextBlockPage() }
        )
    }

    @ViewBuilder
    private var drawerOverlay: some View {
        if viewModel.isDrawerOpen {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { viewModel.isDrawerOpen = false }
            DrawerView(
                user: AuthService.shared.currentUser,
                unreadMailCount: unreadMailCount,
                onSettings: {
                    viewModel.isDrawerOpen = false
                    viewModel.isSettingsOpen = true
                },
                onGuide: {
                    viewModel.isDrawerOpen = false
                    showGuideSheet = true
                },
                onInbox: {
                    viewModel.isDrawerOpen = false
                    showInboxSheet = true
                },
                onSendFeedback: {
                    viewModel.isDrawerOpen = false
                    showAppFeedbackSheet = true
                },
                onEditHandle: {
                    viewModel.isDrawerOpen = false
                    showEditHandleSheet = true
                },
                onSignOut: {
                    AuthService.shared.signOut()
                    viewModel.isDrawerOpen = false
                },
                onDeleteAccount: {
                    showDeleteAccountConfirm = true
                },
                onClose: { viewModel.isDrawerOpen = false }
            )
            .frame(width: 280)
            .transition(.move(edge: .leading))
        }
    }

    @ViewBuilder
    private var sidebarOverlay: some View {
        if viewModel.isSidebarOpen {
            HStack {
                Spacer()
                VariationSidebar(
                    variations: viewModel.allCachedVariations,
                    mushafID: viewModel.mushafID,
                    onSelect: { variation in
                        viewModel.activeWordID = variation.wordID
                    },
                    onClose: { viewModel.isSidebarOpen = false }
                )
            }
            .transition(.move(edge: .trailing))
        }
    }

    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await AuthService.shared.deleteAccount()
            bundleStore.removeSyncedBundles()
            viewModel.isDrawerOpen = false
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    private func refreshUnreadMailCount() async {
        guard auth.isSignedIn else {
            unreadMailCount = 0
            return
        }
        do {
            unreadMailCount = try await MessagesService().unreadCount()
        } catch {
            // Keep last known count if refresh fails.
        }
    }

    private var paintModeEntryButton: some View {
        let isSignedIn = AuthService.shared.isSignedIn
        let isMarking = viewModel.isSelfMarking || (viewModel.isCoachingFriend && viewModel.isMarkingMode)
        let markColor = MarkTypeAppearance.color(for: viewModel.activeMarkType)

        return Button {
            if isSignedIn {
                viewModel.toggleSelfMarkingFromEntry()
            } else {
                viewModel.togglePaintMode()
            }
        } label: {
            Image(systemName: isSignedIn ? "highlighter" : "paintbrush.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    isMarking
                        ? .black
                        : (viewModel.isDarkMode ? .white : .black)
                )
                .frame(width: 44, height: 44)
                .background(
                    isMarking
                        ? markColor
                        : (viewModel.isDarkMode ? Color.white.opacity(0.10) : Color.white)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isMarking
                                ? Color.clear
                                : (viewModel.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14)),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSignedIn ? "Mark Mushaf" : "Paint mode")
    }

    private var ayahPromptEntryButton: some View {
        let isOn = viewModel.isAyahPromptMode
        let dark = viewModel.isDarkMode
        let foreground: Color = isOn
            ? (dark ? .black : .white)
            : (dark ? .white : .black)
        let fill: Color = isOn
            ? (dark ? .white : .black)
            : (dark ? Color.white.opacity(0.10) : .white)
        let stroke: Color = isOn
            ? .clear
            : (dark ? Color.white.opacity(0.14) : Color.black.opacity(0.14))

        return Button {
            viewModel.toggleAyahPromptMode()
        } label: {
            Image("HoldingHands")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(stroke, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isJournalRecording)
        .accessibilityLabel(isOn ? "Exit ayah prompt mode" : "Ayah prompt mode")
    }

    private var journalRecordEntryButton: some View {
        let recording = viewModel.isJournalRecording
        return Button {
            Task { await viewModel.toggleJournalRecording() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(recording ? Color.white : Color.red)
                .frame(width: 44, height: 44)
                .background(
                    recording
                        ? Color.red
                        : (viewModel.isDarkMode ? Color.white.opacity(0.10) : Color.white)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            recording
                                ? Color.clear
                                : (viewModel.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14)),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording ? "Stop recording" : "Record")
    }

    @ViewBuilder
    private func spreadOrPageContent(identityPage: Int) -> some View {
        let spread = MushafSpread.forDisplay(
            containing: identityPage,
            totalPages: viewModel.totalPages,
            allowedPages: viewModel.bundleSession?.pages,
            showsSpread: showsSpread
        )

        if showsSpread, spread.leftPage != nil {
            LandscapeSpreadScrollView(isDarkMode: viewModel.isDarkMode) {
                HStack(spacing: 0) {
                    if let leftPage = spread.leftPage {
                        // Even page (screen left): extra padding on the spine (trailing) side.
                        pageContent(leftPage, fillsHalfSpread: true, gutterEdge: .trailing)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .overlay(alignment: .trailing) {
                                bookGutterShadow(edge: .trailing)
                            }
                    }
                    // Odd page (screen right): extra padding on the spine (leading) side.
                    pageContent(spread.rightPage, fillsHalfSpread: true, gutterEdge: .leading)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .overlay(alignment: .leading) {
                            bookGutterShadow(edge: .leading)
                        }
                }
                .padding(.bottom, 24)
            }
            .id("spread-scroll-\(identityPage)-\(viewModel.mushafReloadToken)")
        } else if showsSpread {
            LandscapeSpreadScrollView(isDarkMode: viewModel.isDarkMode) {
                pageContent(spread.rightPage, fillsHalfSpread: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.bottom, 24)
            }
            .id("spread-scroll-\(identityPage)-\(viewModel.mushafReloadToken)")
        } else {
            pageContent(spread.rightPage, fillsHalfSpread: false)
                .padding(.horizontal, 4)
        }
    }

    /// Soft spine crease between facing pages.
    private func bookGutterShadow(edge: HorizontalEdge) -> some View {
        let colors: [Color] = edge == .trailing
            ? [
                Color.clear,
                Color.black.opacity(0.03),
                Color.black.opacity(0.10),
                Color.black.opacity(0.22)
            ]
            : [
                Color.black.opacity(0.26),
                Color.black.opacity(0.12),
                Color.black.opacity(0.04),
                Color.clear
            ]

        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 28)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pageContent(
        _ pageNumber: Int,
        fillsHalfSpread: Bool,
        gutterEdge: HorizontalEdge? = nil
    ) -> some View {
        if let page = viewModel.pages[pageNumber] {
            PageView(
                page: page,
                mushafID: viewModel.mushafID,
                isDarkMode: viewModel.isDarkMode,
                isJuzFirstLine: viewModel.isJuzFirstLine,
                variationLookup: viewModel.variationLookup,
                activeWordID: viewModel.activeWordID,
                paintedWords: viewModel.displayPaintedWords,
                arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
                isPaintInverted: viewModel.isPaintInverted,
                isAyahPromptMode: viewModel.isAyahPromptMode,
                ayahPromptVisibleWordIDs: viewModel.ayahPromptVisibleWordIDs,
                sessionMarks: viewModel.displaySessionMarks,
                areSessionMarksVisible: viewModel.areSessionMarksVisible,
                isSessionMarksInverted: viewModel.isSessionMarksInverted,
                sessionMarkColors: MarkTypeAppearance.uiColorMap(),
                sessionMarkHeatCounts: viewModel.sessionMarkHeatCounts,
                isFireMode: viewModel.isFireMode,
                contentPushOffset: mushafPushOffset,
                fillsHalfSpread: fillsHalfSpread,
                gutterEdge: gutterEdge,
                pageHeader: viewModel.pageHeaderInfo(for: pageNumber),
                allowsRangeHighlight: viewModel.allowsRangeHighlight,
                verseSearchHighlightWordIDs: viewModel.verseSearchHighlightWordIDs(for: pageNumber),
                highlightedSurahHeader: viewModel.highlightedSurahHeader(for: pageNumber),
                onWordTap: { word in Task { await viewModel.handleWordTap(word, pageNumber: pageNumber) } },
                onWordTapOnPage: { word, wordPage in Task { await viewModel.handleWordTap(word, pageNumber: wordPage) } },
                onActiveWordFrameChange: { frame in
                    if pageNumber == viewModel.currentPage || pageNumber == viewModel.activeSpread.leftPage {
                        activeWordScreenFrame = frame
                    }
                }
            )
            .id("\(viewModel.mushafReloadToken.uuidString)-\(viewModel.mushafID)-\(pageNumber)-\(page.id)")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .task { await viewModel.loadPage(pageNumber) }
        }
    }
}

/// Landscape Mushaf scroll with thin progress rails on both sides.
private struct LandscapeSpreadScrollView<Content: View>: View {
    let isDarkMode: Bool
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var contentMinY: CGFloat = 0

    private var canScroll: Bool {
        contentHeight > viewportHeight + 8
    }

    private var scrollableDistance: CGFloat {
        max(contentHeight - viewportHeight, 1)
    }

    /// 0 at top … 1 at bottom.
    private var progress: CGFloat {
        min(1, max(0, -contentMinY / scrollableDistance))
    }

    private var thumbRatio: CGFloat {
        guard contentHeight > 0 else { return 1 }
        return min(1, max(0.12, viewportHeight / contentHeight))
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: SpreadScrollMetricsKey.self,
                                value: SpreadScrollMetrics(
                                    contentHeight: geo.size.height,
                                    minY: geo.frame(in: .named("spreadScroll")).minY
                                )
                            )
                        }
                    )
            }
            .coordinateSpace(name: "spreadScroll")
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .onPreferenceChange(SpreadScrollMetricsKey.self) { metrics in
                contentHeight = metrics.contentHeight
                contentMinY = metrics.minY
            }
            .onAppear {
                viewportHeight = viewport.size.height
            }
            .onChange(of: viewport.size.height) { _, height in
                viewportHeight = height
            }
            .overlay {
                if canScroll {
                    HStack {
                        scrollRail
                        Spacer(minLength: 0)
                        scrollRail
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 3)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var scrollRail: some View {
        GeometryReader { rail in
            let trackHeight = rail.size.height
            let thumbHeight = max(28, trackHeight * thumbRatio)
            let travel = max(trackHeight - thumbHeight, 0)
            let thumbY = travel * progress

            ZStack(alignment: .top) {
                Capsule()
                    .fill(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                    .frame(width: 3)

                Capsule()
                    .fill(isDarkMode ? Color.white.opacity(0.55) : Color.black.opacity(0.35))
                    .frame(width: 3, height: thumbHeight)
                    .offset(y: thumbY)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 3)
    }
}

private struct SpreadScrollMetrics: Equatable {
    var contentHeight: CGFloat
    var minY: CGFloat
}

private struct SpreadScrollMetricsKey: PreferenceKey {
    static var defaultValue = SpreadScrollMetrics(contentHeight: 0, minY: 0)

    static func reduce(value: inout SpreadScrollMetrics, nextValue: () -> SpreadScrollMetrics) {
        value = nextValue()
    }
}

private struct VersePanelTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}
