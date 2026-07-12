import SwiftUI

struct ReciteTabView: View {
    @Bindable var viewModel: ReciteViewModel
    @Bindable var bundleStore: BundleStore
    let onCreateBundle: () -> Void
    @State private var goPageField = ""
    @State private var activeWordScreenFrame: CGRect?
    @State private var versePanelTopY: CGFloat?

    private var showingVerseOverlay: Bool {
        !viewModel.isPaintMode && viewModel.selectedVerse != nil
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
        hasher.combine(viewModel.paintedWords)
        hasher.combine(viewModel.arePaintedWordsVisible)
        hasher.combine(viewModel.isPaintInverted)
        hasher.combine(viewModel.sessionMarks)
        hasher.combine(viewModel.isMarkingMode)
        hasher.combine(viewModel.activeWordID)
        hasher.combine(viewModel.selectedVerse)
        hasher.combine(mushafPushOffset)
        hasher.combine(viewModel.pages[viewModel.currentPage]?.id)
        return hasher.finalize()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                MushafTopBar(
                    currentPage: viewModel.currentPage,
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
                        onToggleMarking: { viewModel.toggleMarkingMode() },
                        onSelectMarkType: { viewModel.setActiveMarkType($0) },
                        onEnd: { Task { await viewModel.endReviewSession() } }
                    )
                }

                ZStack {
                    Color.white
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
                            contentStamp: mushafContentStamp
                        ) { page in
                            AnyView(
                                pageContent(page)
                                    .padding(.horizontal, 13)
                            )
                        }
                        .id(viewModel.mushafReloadToken)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let session = viewModel.bundleSession {
                        BundleMushafSegmentBar(
                            session: session,
                            onSelect: { viewModel.goToBundlePage(at: $0) },
                            onExit: { viewModel.exitBundleMushaf() }
                        )
                    }
                    if !showingVerseOverlay {
                        ReciteBottomChrome(
                            isPaintMode: viewModel.isPaintMode,
                            isMarkingMode: viewModel.isMarkingMode,
                            isReviewListener: viewModel.isReviewListener,
                            activeMarkType: viewModel.activeMarkType,
                            onToggleMarkingMode: { viewModel.toggleMarkingMode() },
                            onSelectMarkType: { viewModel.setActiveMarkType($0) },
                            selectedVerse: nil,
                            activePaintStyle: viewModel.activePaintStyle,
                            arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
                            isPaintInverted: viewModel.isPaintInverted,
                            hasPaintedWords: !viewModel.paintedWords.isEmpty,
                            onTogglePaintMode: { viewModel.togglePaintMode() },
                            onTogglePaintedWordsVisible: { viewModel.togglePaintedWordsVisible() },
                            onSelectPaintStyle: viewModel.setActivePaintStyle,
                            onTogglePaintInverted: { viewModel.togglePaintInverted() },
                            onDismissVerseRef: { viewModel.clearSelectedVerseRef() }
                        )
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showingVerseOverlay {
                    ReciteBottomChrome(
                        isPaintMode: false,
                        isMarkingMode: viewModel.isMarkingMode,
                        isReviewListener: viewModel.isReviewListener,
                        activeMarkType: viewModel.activeMarkType,
                        onToggleMarkingMode: { viewModel.toggleMarkingMode() },
                        onSelectMarkType: { viewModel.setActiveMarkType($0) },
                        selectedVerse: viewModel.selectedVerse,
                        activePaintStyle: viewModel.activePaintStyle,
                        arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
                        isPaintInverted: viewModel.isPaintInverted,
                        hasPaintedWords: !viewModel.paintedWords.isEmpty,
                        onTogglePaintMode: { viewModel.togglePaintMode() },
                        onTogglePaintedWordsVisible: { viewModel.togglePaintedWordsVisible() },
                        onSelectPaintStyle: viewModel.setActivePaintStyle,
                        onTogglePaintInverted: { viewModel.togglePaintInverted() },
                        onDismissVerseRef: { viewModel.clearSelectedVerseRef() }
                    )
                    .background(Color.white)
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
                    parents: viewModel.parentNarrators,
                    expandedParents: Binding(
                        get: { viewModel.expandedParentIDs },
                        set: { viewModel.expandedParentIDs = $0 }
                    ),
                    selectedIDs: Set(viewModel.selectedNarratorIDs),
                    onToggle: viewModel.toggleNarrator,
                    onSettings: {
                        viewModel.isDrawerOpen = false
                        viewModel.isSettingsOpen = true
                    },
                    onClose: { viewModel.isDrawerOpen = false }
                )
                .frame(width: 300)
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
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func pageContent(_ pageNumber: Int) -> some View {
        if let page = viewModel.pages[pageNumber] {
            PageView(
                page: page,
                mushafID: viewModel.mushafID,
                isDarkMode: viewModel.isDarkMode,
                isJuzFirstLine: viewModel.isJuzFirstLine,
                variationLookup: viewModel.variationLookup,
                activeWordID: viewModel.activeWordID,
                paintedWords: viewModel.paintedWords,
                arePaintedWordsVisible: viewModel.arePaintedWordsVisible,
                isPaintInverted: viewModel.isPaintInverted,
                sessionMarks: viewModel.sessionMarks,
                contentPushOffset: mushafPushOffset,
                onWordTap: { word in Task { await viewModel.handleWordTap(word) } },
                onActiveWordFrameChange: { frame in
                    if pageNumber == viewModel.currentPage {
                        activeWordScreenFrame = frame
                    }
                }
            )
            .id("\(viewModel.mushafReloadToken.uuidString)-\(viewModel.mushafID)-\(pageNumber)-\(page.id)")
        } else {
            ProgressView()
                .task { await viewModel.loadPage(pageNumber) }
        }
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
