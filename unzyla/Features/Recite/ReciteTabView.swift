import SwiftUI

struct ReciteTabView: View {
    @Bindable var viewModel: ReciteViewModel
    @Bindable var bundleStore: BundleStore
    @Binding var selectedTab: Int
    let onCreateBundle: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var goPageField = ""
    @State private var activeWordScreenFrame: CGRect?
    @State private var versePanelTopY: CGFloat?
    @State private var showAppFeedbackSheet = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    private var showsSpread: Bool {
        verticalSizeClass == .compact
    }

    private var showingVerseOverlay: Bool {
        !viewModel.isPaintMode && viewModel.selectedVerse != nil
    }

    private var hasPaintOnVisiblePages: Bool {
        viewModel.hasPaintedWordsOnVisiblePages
    }

    /// Full paint options when actively painting or visible pages have paints.
    private var shouldShowPaintTools: Bool {
        viewModel.isPaintMode || hasPaintOnVisiblePages
    }

    /// Bottom chrome: review tools, paint tools, or landscape tabs.
    private var shouldShowBottomChrome: Bool {
        viewModel.isReviewListener || shouldShowPaintTools || showsSpread
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

    private var mushafPushOffset: CGFloat {
        guard showingVerseOverlay,
              let wordFrame = activeWordScreenFrame,
              let panelTop = versePanelTopY
        else { return 0 }

        let margin: CGFloat = 14
        return max(0, wordFrame.maxY - panelTop + margin)
    }

    private var mushafContentStamp: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.isPaintMode)
        hasher.combine(viewModel.activePaintStyle)
        hasher.combine(viewModel.displayPaintedWords)
        hasher.combine(viewModel.arePaintedWordsVisible)
        hasher.combine(viewModel.isPaintInverted)
        hasher.combine(viewModel.sessionMarks)
        hasher.combine(viewModel.isMarkingMode)
        hasher.combine(viewModel.pageHidden)
        hasher.combine(viewModel.activeWordID)
        hasher.combine(viewModel.selectedVerse)
        hasher.combine(mushafPushOffset)
        hasher.combine(showsSpread)
        hasher.combine(viewModel.pages[viewModel.currentPage]?.id)
        if let left = viewModel.activeSpread.leftPage {
            hasher.combine(viewModel.pages[left]?.id)
        }
        return hasher.finalize()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                MushafTopBar(
                    currentPage: viewModel.currentPage,
                    pageLabel: showsSpread ? viewModel.activeSpread.displayLabel : nil,
                    selectedNarratorIDs: viewModel.selectedNarratorIDs,
                    parentNarrators: viewModel.parentNarrators,
                    onMenu: { viewModel.isDrawerOpen = true },
                    onSearch: {
                        goPageField = String(viewModel.currentPage)
                        viewModel.isGoToPageOpen = true
                    },
                    onAddToBundle: { viewModel.isAddToBundleOpen = true }
                )

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
                            isPagingEnabled: viewModel.isReviewPagingEnabled,
                            showsSpread: showsSpread
                        ) { identityPage in
                            AnyView(
                                spreadOrPageContent(identityPage: identityPage)
                            )
                        }
                        .id("\(viewModel.mushafReloadToken)-\(showsSpread)")
                    }

                    if viewModel.isReviewActive, !viewModel.isReviewListener, viewModel.pageHidden {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(reciteShellBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let session = viewModel.bundleSession {
                        BundleMushafSegmentBar(
                            session: session,
                            onSelect: { viewModel.goToBundlePage(at: $0) },
                            onExit: {
                                if viewModel.isReviewActive {
                                    Task { await viewModel.endReviewSession() }
                                } else {
                                    viewModel.exitBundleMushaf()
                                }
                            }
                        )
                        .frame(height: showsSpread ? 34 : 44)
                    }
                    if !showingVerseOverlay {
                        if shouldShowBottomChrome {
                            ReciteBottomChrome(
                                isPaintMode: viewModel.isPaintMode,
                                isMarkingMode: viewModel.isMarkingMode,
                                isReviewListener: viewModel.isReviewListener,
                                pageHidden: viewModel.pageHidden,
                                isCompactLandscape: showsSpread,
                                isDarkMode: viewModel.isDarkMode,
                                showsPaintTools: shouldShowPaintTools || viewModel.isReviewListener,
                                selectedTab: $selectedTab,
                                activeMarkType: viewModel.activeMarkType,
                                onToggleMarkingMode: { viewModel.toggleMarkingMode() },
                                onSelectMarkType: { viewModel.setActiveMarkType($0) },
                                onTogglePageHidden: { viewModel.togglePageHidden() },
                                selectedVerse: nil,
                                activePaintStyle: viewModel.activePaintStyle,
                                arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
                                isPaintInverted: viewModel.isPaintInverted,
                                hasPaintedWords: hasPaintOnVisiblePages,
                                onTogglePaintMode: { viewModel.togglePaintMode() },
                                onTogglePaintedWordsVisible: { viewModel.togglePaintedWordsVisible() },
                                onSelectPaintStyle: viewModel.setActivePaintStyle,
                                onTogglePaintInverted: { viewModel.togglePaintInverted() },
                                onDismissVerseRef: { viewModel.clearSelectedVerseRef() }
                            )
                        } else {
                            paintModeEntryButton
                                .padding(.leading, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .background(bottomBarBackground)
                .overlay(alignment: .top) {
                    if !shouldShowBottomChrome || showingVerseOverlay {
                        Rectangle()
                            .fill(viewModel.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            .frame(height: 1 / UIScreen.main.scale)
                    }
                }
            }
            .toolbar(showsSpread ? .hidden : .automatic, for: .tabBar)
            .overlay(alignment: .bottom) {
                if showingVerseOverlay {
                    ReciteBottomChrome(
                        isPaintMode: false,
                        isMarkingMode: viewModel.isMarkingMode,
                        isReviewListener: viewModel.isReviewListener,
                        pageHidden: viewModel.pageHidden,
                        isCompactLandscape: showsSpread,
                        isDarkMode: viewModel.isDarkMode,
                        showsPaintTools: shouldShowPaintTools || viewModel.isReviewListener,
                        selectedTab: $selectedTab,
                        activeMarkType: viewModel.activeMarkType,
                        onToggleMarkingMode: { viewModel.toggleMarkingMode() },
                        onSelectMarkType: { viewModel.setActiveMarkType($0) },
                        onTogglePageHidden: { viewModel.togglePageHidden() },
                        selectedVerse: viewModel.selectedVerse,
                        activePaintStyle: viewModel.activePaintStyle,
                        arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
                        isPaintInverted: viewModel.isPaintInverted,
                        hasPaintedWords: hasPaintOnVisiblePages,
                        onTogglePaintMode: { viewModel.togglePaintMode() },
                        onTogglePaintedWordsVisible: { viewModel.togglePaintedWordsVisible() },
                        onSelectPaintStyle: viewModel.setActivePaintStyle,
                        onTogglePaintInverted: { viewModel.togglePaintInverted() },
                        onDismissVerseRef: { viewModel.clearSelectedVerseRef() }
                    )
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

            if viewModel.isDrawerOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.isDrawerOpen = false }
                DrawerView(
                    user: AuthService.shared.currentUser,
                    onSettings: {
                        viewModel.isDrawerOpen = false
                        viewModel.isSettingsOpen = true
                    },
                    onSendFeedback: {
                        viewModel.isDrawerOpen = false
                        showAppFeedbackSheet = true
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.isDrawerOpen)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSidebarOpen)
        .animation(.easeInOut(duration: 0.2), value: viewModel.pageHidden)
        .onAppear {
            viewModel.setPrefersSpreadLayout(showsSpread)
        }
        .onChange(of: showsSpread) { _, isSpread in
            viewModel.setPrefersSpreadLayout(isSpread)
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
                onGo: viewModel.goToPage
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isAddToBundleOpen },
            set: { viewModel.isAddToBundleOpen = $0 }
        )) {
            AddPageToBundleSheet(
                currentPage: viewModel.currentPage,
                bundleStore: bundleStore,
                onCreateBundle: {
                    viewModel.isAddToBundleOpen = false
                    onCreateBundle()
                }
            )
        }
        .sheet(isPresented: $showAppFeedbackSheet) {
            SendAppFeedbackSheet()
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

    private var paintModeEntryButton: some View {
        Button {
            viewModel.togglePaintMode()
        } label: {
            Image(systemName: "paintbrush.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(viewModel.isDarkMode ? .white : .black)
                .frame(width: 44, height: 44)
                .background(viewModel.isDarkMode ? Color.white.opacity(0.10) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            viewModel.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paint mode")
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
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }
            .id("spread-scroll-\(identityPage)-\(viewModel.mushafReloadToken)")
        } else if showsSpread {
            LandscapeSpreadScrollView(isDarkMode: viewModel.isDarkMode) {
                pageContent(spread.rightPage, fillsHalfSpread: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 24)
            }
            .id("spread-scroll-\(identityPage)-\(viewModel.mushafReloadToken)")
        } else {
            pageContent(spread.rightPage, fillsHalfSpread: false)
                .padding(.horizontal, 13)
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
                sessionMarks: viewModel.isReviewListener ? viewModel.sessionMarks : [:],
                contentPushOffset: mushafPushOffset,
                fillsHalfSpread: fillsHalfSpread,
                gutterEdge: gutterEdge,
                onWordTap: { word in Task { await viewModel.handleWordTap(word, pageNumber: pageNumber) } },
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
