import Foundation
import Observation
import UIKit

struct BundleMushafSession: Equatable {
    let bundleID: UUID
    let title: String
    let pages: [Int]
    var currentIndex: Int
    /// Display grouping overrides (boundary pages that belong with the next/previous surah).
    var pageSurahOverrides: [Int: Int] = [:]

    var groups: [BundlePageGroup] {
        BundlePageGrouping.groups(for: pages, surahOverrides: pageSurahOverrides)
    }
}

struct TraversalItem: Identifiable, Hashable {
    let id: String
    let wordID: Int
    let hafsText: String
    let variationText: String
    let narratorID: String
    let narratorTitle: String
    let narratorColor: String
}

struct DeckEndRangeSelection: Equatable {
    let startPage: Int
    let suggestedTitle: String?
}

struct PendingNewDeck: Equatable {
    let pages: [Int]
    let suggestedTitle: String?
}

struct VerseSearchHighlight: Equatable, Hashable {
    let page: Int
    let verseKey: String
}

/// A surah header briefly lit up after jumping to that surah's start.
struct SurahHeaderHighlight: Equatable, Hashable {
    let page: Int
    let surah: Int
}

@MainActor
@Observable
final class ReciteViewModel {
    private let api = APIClient.shared
    private let pageCache = PageCache()
    private let variationCache = VariationCache()
    private let prefs = PreferencesStore.shared

    var mushafID: Int
    var mushafReloadToken = UUID()
    var isMushafSwitching = false
    var currentPage = 9
    var totalPages = 604
    var isDarkMode: Bool
    var translationLanguage: TranslationLanguage
    var isTajweedMarkingEnabled: Bool
    var isLoading = true
    var errorMessage: String?

    var parentNarrators: [ParentNarrator] = []
    var selectedNarratorIDs: [String] = []
    var expandedParentIDs: Set<Int> = []

    var pages: [Int: MushafPage] = [:]
    var juzSegments: [NavigationSegment] = []
    var surahSegments: [NavigationSegment] = []

    var isDrawerOpen = false
    var isSettingsOpen = false
    var isGoToPageOpen = false
    var isAddToBundleOpen = false
    var isVariationSheetExpanded = false
    var isSidebarOpen = false

    /// When set, user is swiping to choose the end page for a new deck.
    var deckEndRangeSelection: DeckEndRangeSelection?
    /// Pages + title suggestion handed to the create-deck sheet.
    var pendingNewDeck: PendingNewDeck?

    var activeWordID: Int?
    var selectedVerse: SelectedVerseDetail?
    var verseSearchHighlight: VerseSearchHighlight?
    /// Bumped when highlight should re-apply (e.g. page ayah data arrived after navigate).
    var verseSearchHighlightEpoch = 0
    var surahHeaderHighlight: SurahHeaderHighlight?
    var traversalIndex = 0

    var isPaintMode = false
    var isAyahPromptMode = false
    var ayahPromptRevealedWordIDs: Set<Int> = []
    /// Cue blocks after verse endings in helper mode (0 = circles only, default 2).
    var ayahPromptCueCount = 2
    var activePaintStyle: WordPaintStyle = .highlight
    var paintedWords: [Int: WordPaintStyle] = [:]
    var arePaintedWordsVisible = true
    var isPaintInverted = false
    /// Live preview while hold-dragging to activate a highlight/mark range.
    var rangeHighlightPreviewIDs: Set<Int> = []
    private var rangeHighlightAnchorWordID: Int?
    var isRangeHighlightDragging: Bool { rangeHighlightAnchorWordID != nil }
    /// Prior paint canvas stashed while a deck recording is in progress.
    private var recordingPaintSnapshot: [Int: WordPaintStyle]?
    private(set) var isDeckRecordingSession = false
    /// Local Mushaf journal recording (helper stays on; pages in view are stored).
    private(set) var isJournalRecording = false
    private var journalRecordingPages: Set<Int> = []
    private var journalRecordingStartPage: Int?
    /// Prior paint canvas stashed while reviewing a saved take's marks.
    private var reviewPaintSnapshot: [Int: WordPaintStyle]?
    private(set) var isReviewingDeckRecording = false

    var reviewSession: ReviewSessionContext?
    var isMarkingMode = false
    var isFireMode = false
    var activeMarkType: MistakeMarkType = .mistake
    var sessionMarks: [Int: MistakeMarkType] = [:]
    var sessionMarkIDs: [Int: UUID] = [:]
    /// Word → heat count for persisted mushaf marks.
    var sessionMarkHeatCounts: [Int: Int] = [:]
    /// Session-mark word → persisted mushaf_mark id (so live review also lands in Feedback).
    private var sessionPersistedMushafMarkIDs: [Int: UUID] = [:]
    /// Hide/show persisted Mushaf marks when viewing your own page.
    var areSessionMarksVisible = true
    /// Invert so only marked words remain visible (own Mushaf).
    var isSessionMarksInverted = false
    /// Past feedback review: show listener marks on the deck Mushaf (read-only).
    var isViewingFeedbackMarks = false
    /// Word → page for persisted / session marks (so arrows can jump beyond loaded pages).
    private var markWordPages: [Int: Int] = [:]
    /// Word → page for local paint blocks.
    private var paintedWordPages: [Int: Int] = [:]
    /// When set (Feedback filters), arrows only visit these pages.
    var feedbackBlockPages: Set<Int>?
    /// Friend whose Mushaf we are marking. `nil` means default: mark your own.
    var coachSubject: HifzworldUser?
    var pageHidden = false
    /// When true (landscape), navigation uses odd-right / even-left spreads.
    var prefersSpreadLayout = false
    private var reviewPollTask: Task<Void, Never>?
    private var isApplyingRemotePage = false
    /// Ignores stale pager callbacks while swapping from one active deck to another.
    private var isActivatingBundle = false
    private var isFlushingPendingMarks = false
    private let pendingMarks = PendingMushafMarksStore.shared
    private var hydrationTask: Task<Void, Never>?
    private var hydrationGeneration = 0
    private var hydrationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private static let pageRefreshInterval: TimeInterval = 180

    var isReviewListener: Bool { reviewSession?.role == .listener }
    var isReviewActive: Bool { reviewSession != nil }
    var isReviewPagingEnabled: Bool { !isReviewActive || isReviewListener }
    /// Marking someone else's Mushaf (shows banner + Exit).
    var isCoachingFriend: Bool {
        guard let coachSubject else { return false }
        guard let me = AuthService.shared.currentUser else { return true }
        return coachSubject.id != me.id
    }
    /// Actively marking own Mushaf (default when no friend selected).
    var isSelfMarking: Bool {
        AuthService.shared.currentUser != nil && coachSubject == nil && isMarkingMode && !isReviewListener
    }
    /// Friend override or self marking session.
    var isCoaching: Bool { isCoachingFriend || isSelfMarking }
    var isMistakeMarkingActive: Bool { isReviewListener || isCoaching }

    /// Whose Mushaf marks apply to — friend if selected, otherwise current user.
    var markSubject: HifzworldUser? {
        coachSubject ?? AuthService.shared.currentUser
    }

    /// Load/show persisted Mushaf marks for the current subject (self by default).
    var shouldReloadMushafMarks: Bool {
        !isViewingFeedbackMarks
            && !isReviewActive
            && markSubject != nil
    }

    var activeSpread: MushafSpread {
        MushafSpread.forDisplay(
            containing: currentPage,
            totalPages: totalPages,
            allowedPages: bundleSession?.pages,
            showsSpread: prefersSpreadLayout
        )
    }

    /// Pages currently on screen (one in portrait, spread pair in landscape).
    var visiblePageNumbers: [Int] {
        prefersSpreadLayout ? activeSpread.pages : [currentPage]
    }

    /// Whether any user-painted words exist on the currently visible page(s).
    var hasPaintedWordsOnVisiblePages: Bool {
        guard !paintedWords.isEmpty else { return false }
        for pageNumber in visiblePageNumbers {
            guard let page = pages[pageNumber] else { continue }
            for line in page.lines {
                for word in line.words where paintedWords[word.id] != nil {
                    return true
                }
            }
        }
        return false
    }

    /// Reciter sees listener marks as blackout; feedback review maps marks to the active paint style.
    var displayPaintedWords: [Int: WordPaintStyle] {
        if isViewingFeedbackMarks {
            var map: [Int: WordPaintStyle] = [:]
            for wordID in sessionMarks.keys {
                map[wordID] = activePaintStyle
            }
            return map
        }
        var map: [Int: WordPaintStyle]
        if isReviewActive, !isReviewListener {
            map = paintedWords
            for wordID in sessionMarks.keys {
                map[wordID] = .blackout
            }
        } else {
            map = paintedWords
        }
        if isPaintMode {
            for wordID in rangeHighlightPreviewIDs where map[wordID] == nil {
                map[wordID] = activePaintStyle
            }
        }
        return map
    }

    /// Session / coach marks including live range-activation preview.
    var displaySessionMarks: [Int: MistakeMarkType] {
        var map = sessionMarks
        if isMistakeMarkingActive, isMarkingMode {
            for wordID in rangeHighlightPreviewIDs where map[wordID] == nil {
                map[wordID] = activeMarkType
            }
        }
        return map
    }

    /// Hold-drag range activate is available in paint or marking modes.
    var allowsRangeHighlight: Bool {
        if isViewingFeedbackMarks || isAyahPromptMode || isFireMode { return false }
        if isPaintMode { return true }
        if isMistakeMarkingActive, isMarkingMode { return true }
        return false
    }

    /// Whether any Mushaf marks exist on the currently visible page(s).
    var hasSessionMarksOnVisiblePages: Bool {
        guard !sessionMarks.isEmpty else { return false }
        for pageNumber in visiblePageNumbers {
            guard let page = pages[pageNumber] else { continue }
            for line in page.lines {
                for word in line.words where sessionMarks[word.id] != nil {
                    return true
                }
            }
        }
        return false
    }

    /// Whether feedback marks (or paints) exist on the currently visible page(s).
    var hasFeedbackMarksOnVisiblePages: Bool {
        guard isViewingFeedbackMarks else { return false }
        return hasSessionMarksOnVisiblePages
    }

    var iosUpdateWall: MinVersionCheckResult?

    var bundleSession: BundleMushafSession?

    var isBundleMushafMode: Bool { bundleSession != nil }

    private let bundledSegments = SegmentsLoader.loadBundledSegments()
    private let verseTranslationsService = VerseTranslationsService()
    private var pageLoadTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var verseTranslationTask: Task<Void, Never>?
    @ObservationIgnored private var verseSearchHighlightClearTask: Task<Void, Never>?
    @ObservationIgnored private var surahHeaderHighlightClearTask: Task<Void, Never>?
    @ObservationIgnored private var verseTranslationPrefetchTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var verseTranslationCache: [String: String] = [:]

    private static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    init() {
        mushafID = prefs.mushafID
        isDarkMode = prefs.isMushafDarkMode
        translationLanguage = prefs.translationLanguage
        isTajweedMarkingEnabled = prefs.isTajweedMarkingEnabled
        selectedNarratorIDs = prefs.selectedNarratorIDs
        ayahPromptCueCount = prefs.ayahPromptCueCount
        if let saved = prefs.lastPage(forMushaf: mushafID) {
            currentPage = saved
        }
    }

    var comparisonNarratorID: String? {
        selectedNarratorIDs.first { $0 != NarratorCatalog.hafsID }
    }

    var pageVariations: [Variation] {
        guard let page = pages[currentPage] else { return [] }
        return variationCache.variations(on: page)
            .filter { selectedNarratorIDs.contains($0.narratorIDString) && $0.narratorIDString != NarratorCatalog.hafsID }
    }

    var allCachedVariations: [Variation] {
        variationCache.allVariations()
            .filter { selectedNarratorIDs.contains($0.narratorIDString) && $0.narratorIDString != NarratorCatalog.hafsID }
    }

    var traversalItems: [TraversalItem] {
        guard let page = pages[currentPage],
              let narratorID = comparisonNarratorID
        else { return [] }

        var items: [TraversalItem] = []
        let narratorTitle = findChildTitle(narratorID) ?? narratorID
        let color = findChildColor(narratorID) ?? "#f9ca24"

        for line in page.lines {
            for word in line.words {
                if let variation = variationCache.variation(wordID: word.id, narratorID: narratorID),
                   variation.content != word.content {
                    items.append(
                        TraversalItem(
                            id: "\(word.id)-\(narratorID)",
                            wordID: word.id,
                            hafsText: word.content,
                            variationText: variation.content,
                            narratorID: narratorID,
                            narratorTitle: narratorTitle,
                            narratorColor: color
                        )
                    )
                }
            }
        }
        return items
    }

    func bootstrap() async {
        await checkMinVersion()
        await loadNarrators()
        await loadMushafMetadata()
        await loadSegments()
        await loadPage(currentPage)
        await prefetchAround(currentPage)
        if shouldReloadMushafMarks {
            await reloadCoachMarksForVisiblePages()
            await refreshMarkBlockPageIndex()
        }
        isLoading = false
        NowPlayingController.shared.wire(to: AudioPlayerService.shared)
        await flushPendingMushafMarksIfNeeded()
        resumeMushafHydration()
    }

    func checkMinVersion() async {
        iosUpdateWall = await GlobalConfigService.checkMinVersion()
    }

    func loadNarrators() async {
        do {
            let dtos = try await api.fetchNarrators()
            parentNarrators = NarratorCatalog.build(from: dtos)
            expandedParentIDs = Set(parentNarrators.map(\.id))
            if selectedNarratorIDs.isEmpty {
                selectedNarratorIDs = [NarratorCatalog.hafsID]
            }
            await refreshBulkVariations()
        } catch {
            if NetworkMonitor.shared.isConnected, !Self.isTransientNetworkFailure(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMushafMetadata() async {
        await pageCache.setMushaf(mushafID)
        do {
            let info = try await api.fetchMushaf(id: mushafID)
            if let total = info.totalPages { totalPages = total }
        } catch {
            if NetworkMonitor.shared.isConnected, !Self.isTransientNetworkFailure(error) {
                errorMessage = error.localizedDescription
            }
        }
        currentPage = min(max(currentPage, 1), max(totalPages, 1))
    }

    func loadSegments() async {
        do {
            let juz = try await api.fetchSegments(mushafID: mushafID, category: "juz")
            let surah = try await api.fetchSegments(mushafID: mushafID, category: "surah")
            if !juz.isEmpty {
                juzSegments = SegmentsLoader.fromAPI(juz)
            }
            if !surah.isEmpty {
                surahSegments = SegmentsLoader.fromAPI(surah)
            }
            if juz.isEmpty || surah.isEmpty {
                let fallback = SegmentsLoader.bundledFallback(mushafID: mushafID, entries: bundledSegments)
                if juz.isEmpty { juzSegments = fallback.juz }
                if surah.isEmpty { surahSegments = fallback.surah }
            }
        } catch {
            let fallback = SegmentsLoader.bundledFallback(mushafID: mushafID, entries: bundledSegments)
            juzSegments = fallback.juz
            surahSegments = fallback.surah
        }
    }

    func loadPage(_ position: Int) async {
        if let existing = pageLoadTasks[position] {
            await existing.value
            return
        }

        let task = Task { @MainActor in
            await loadPageOnce(position)
        }
        pageLoadTasks[position] = task
        await task.value
        pageLoadTasks.removeValue(forKey: position)
    }

    private func loadPageOnce(_ position: Int) async {
        let fetchMushafID = mushafID
        if let cached = await pageCache.page(position) {
            pages[position] = cached
            await loadVariationsForPage(cached)
            prefetchVerseTranslations(for: cached)
            Task { await refreshPageIfNeeded(position) }
            return
        }
        do {
            let page = try await api.fetchPage(mushafID: fetchMushafID, position: position)
            guard mushafID == fetchMushafID else { return }
            await pageCache.store(page)
            pages[position] = page
            await loadVariationsForPage(page)
            prefetchVerseTranslations(for: page)
        } catch {
            guard !Self.isCancelled(error) else { return }
            if !NetworkMonitor.shared.isConnected || Self.isTransientNetworkFailure(error) {
                errorMessage = "Page not downloaded yet. Open this page online once, or keep the app open on Wi‑Fi so the Mushaf can finish caching."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshPageIfNeeded(_ position: Int) async {
        guard NetworkMonitor.shared.isConnected else { return }
        let fetchMushafID = mushafID
        if let fetchedAt = await pageCache.fetchedAt(position),
           Date().timeIntervalSince(fetchedAt) < Self.pageRefreshInterval {
            return
        }
        do {
            let page = try await api.fetchPage(mushafID: fetchMushafID, position: position)
            guard mushafID == fetchMushafID else { return }
            await pageCache.store(page)
            pages[position] = page
            await loadVariationsForPage(page)
            if verseSearchHighlight?.page == position {
                verseSearchHighlightEpoch &+= 1
            }
        } catch {
            // Keep the cached copy; visit refresh is best-effort.
        }
    }

    func enterBundleMushaf(bundle: MushafBundle, startingPage: Int) {
        guard !bundle.pageNumbers.isEmpty else { return }
        if isDeckRecordingSession,
           let active = DeckAudioRecorder.shared.activeDeckID,
           active != bundle.id {
            return
        }

        let previousDeckID = bundleSession?.bundleID
        let isSwitchingDeck = previousDeckID != nil && previousDeckID != bundle.id

        if isViewingFeedbackMarks, isSwitchingDeck || previousDeckID != bundle.id {
            clearFeedbackReviewMarks()
        }
        if isSwitchingDeck {
            clearDeckRecordingReviewMarks()
            if let previousDeckID {
                DeckRecordingPlayer.shared.stopIfPlaying(deckID: previousDeckID)
            }
            mushafReloadToken = UUID()
        }

        let index = bundle.pageNumbers.firstIndex(of: startingPage) ?? 0
        let targetPage = bundle.pageNumbers[index]

        isActivatingBundle = true
        bundleSession = BundleMushafSession(
            bundleID: bundle.id,
            title: bundle.title,
            pages: bundle.pageNumbers,
            currentIndex: index,
            pageSurahOverrides: bundle.pageSurahOverrides
        )
        goToPage(targetPage, force: true)
        resumeMushafHydration(restart: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if bundleSession?.bundleID == bundle.id {
                isActivatingBundle = false
            }
        }
    }

    func exitBundleMushaf() {
        guard !isDeckRecordingSession else { return }
        let deckID = bundleSession?.bundleID
        bundleSession = nil
        isActivatingBundle = false
        clearDeckRecordingReviewMarks()
        clearFeedbackReviewMarks()
        if let deckID {
            DeckRecordingPlayer.shared.stopIfPlaying(deckID: deckID)
        }
    }

    /// Opens the deck, clears paint for a fresh slate, and enables paint mode.
    func beginDeckRecordingSession(bundle: MushafBundle) {
        clearDeckRecordingReviewMarks()
        clearFeedbackReviewMarks()
        recordingPaintSnapshot = paintedWords
        paintedWords = [:]
        syncPaintedWordPagesFromLoadedPages()
        isPaintInverted = false
        arePaintedWordsVisible = true
        activePaintStyle = .highlight
        isPaintMode = true
        selectedVerse = nil
        isDeckRecordingSession = true
        let startPage = bundle.pageNumbers.first ?? currentPage
        enterBundleMushaf(bundle: bundle, startingPage: startPage)
    }

    /// Captures marks from the live canvas and restores the prior paint slate.
    @discardableResult
    func endDeckRecordingSession() -> [Int: WordPaintStyle] {
        let captured = paintedWords
        paintedWords = recordingPaintSnapshot ?? [:]
        recordingPaintSnapshot = nil
        syncPaintedWordPagesFromLoadedPages()
        isDeckRecordingSession = false
        isPaintMode = false
        return captured
    }

    /// Loads a saved take's marks onto the deck Mushaf for review.
    func reviewDeckRecording(_ recording: DeckRecording, bundle: MushafBundle) {
        guard !isDeckRecordingSession else { return }
        clearFeedbackReviewMarks()
        if !isReviewingDeckRecording {
            reviewPaintSnapshot = paintedWords
            isReviewingDeckRecording = true
        }
        let startPage = bundle.pageNumbers.first ?? 1
        enterBundleMushaf(bundle: bundle, startingPage: startPage)
        paintedWords = recording.paintedWords
        syncPaintedWordPagesFromLoadedPages()
        arePaintedWordsVisible = true
        isPaintMode = false
        isPaintInverted = false
    }

    /// Hides take marks when the deck review session ends; restores personal paints.
    func clearDeckRecordingReviewMarks() {
        guard isReviewingDeckRecording else { return }
        paintedWords = reviewPaintSnapshot ?? [:]
        reviewPaintSnapshot = nil
        syncPaintedWordPagesFromLoadedPages()
        isReviewingDeckRecording = false
    }

    /// Opens a past feedback session's deck with listener mistake marks highlighted.
    func reviewFeedbackSession(_ session: FeedbackSessionDTO, bundle: MushafBundle) async {
        guard !isDeckRecordingSession else { return }
        clearDeckRecordingReviewMarks()
        clearFeedbackReviewMarks()
        isPaintMode = false
        isMarkingMode = false
        arePaintedWordsVisible = true
        isPaintInverted = false
        activePaintStyle = .highlight
        activeWordID = nil
        selectedVerse = nil
        verseTranslationTask?.cancel()

        let startPage = session.marks.map(\.pageNumber).min()
            ?? bundle.pageNumbers.first
            ?? currentPage
        enterBundleMushaf(bundle: bundle, startingPage: startPage)

        let markPages = Set(session.marks.map(\.pageNumber)).union([startPage])
        for page in markPages {
            await loadPage(page)
        }

        sessionMarks = Self.sessionMarkMap(from: session.marks)
        isViewingFeedbackMarks = true
        let filteredPages = Set(session.marks.filter { !$0.isUnmarked }.map(\.pageNumber))
        feedbackBlockPages = filteredPages
        for mark in session.marks where !mark.isUnmarked {
            markWordPages[mark.wordID] = mark.pageNumber
        }

        if let first = session.marks.filter({ !$0.isUnmarked }).sorted(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }).first {
            activeWordID = first.wordID
            if bundle.pageNumbers.contains(first.pageNumber) {
                goToPage(first.pageNumber, force: true)
            }
        }
    }

    func clearFeedbackReviewMarks() {
        guard isViewingFeedbackMarks else { return }
        sessionMarks = [:]
        sessionMarkIDs = [:]
        sessionMarkHeatCounts = [:]
        isViewingFeedbackMarks = false
        feedbackBlockPages = nil
        activeWordID = nil
    }

    private static func sessionMarkMap(from marks: [SessionMarkDTO]) -> [Int: MistakeMarkType] {
        var map: [Int: MistakeMarkType] = [:]
        for mark in marks where !mark.isUnmarked {
            map[mark.wordID] = MistakeMarkType.resolved(from: mark.markType)
        }
        return map
    }

    /// Rebuilds the active deck session from the store after pages are added/removed.
    /// Prefer `preferPage` when present in the updated page list; otherwise keep the
    /// current page if possible.
    func reloadBundleSession(from store: BundleStore, preferPage: Int? = nil) {
        guard let session = bundleSession else { return }
        guard let bundle = store.bundle(id: session.bundleID) else {
            exitBundleMushaf()
            return
        }
        let pages = bundle.pageNumbers
        guard !pages.isEmpty else {
            exitBundleMushaf()
            return
        }

        let previousPage = session.pages.indices.contains(session.currentIndex)
            ? session.pages[session.currentIndex]
            : pages[0]
        let target = preferPage.flatMap { pages.contains($0) ? $0 : nil } ?? previousPage
        let index = pages.firstIndex(of: target) ?? pages.firstIndex(of: previousPage) ?? 0

        bundleSession = BundleMushafSession(
            bundleID: bundle.id,
            title: bundle.title,
            pages: pages,
            currentIndex: index,
            pageSurahOverrides: bundle.pageSurahOverrides
        )
        goToPage(pages[index], force: true)
    }

    func goToBundlePage(at index: Int) {
        if isReviewActive, !isReviewListener, !isApplyingRemotePage {
            return
        }
        guard var session = bundleSession else { return }
        let clamped = min(max(index, 0), session.pages.count - 1)
        session.currentIndex = clamped
        bundleSession = session
        goToPage(session.pages[clamped])
    }

    func syncBundleIndex(with page: Int) {
        guard var session = bundleSession else { return }
        if let index = session.pages.firstIndex(of: page) {
            session.currentIndex = index
            bundleSession = session
            return
        }
        // Spread identity may be the odd right while the listener tapped the even partner.
        if prefersSpreadLayout,
           let left = MushafSpread.natural(containing: page, totalPages: totalPages).leftPage,
           let index = session.pages.firstIndex(of: left) {
            session.currentIndex = index
            bundleSession = session
            return
        }
        // While swapping decks, the pager can still report the previous page once —
        // don't tear down the newly activated deck.
        if isActivatingBundle || isDeckRecordingSession {
            return
        }
        exitBundleMushaf()
    }

    func goToPage(_ page: Int, force: Bool = false) {
        if !force, isReviewActive, !isReviewListener, !isApplyingRemotePage {
            return
        }
        let clamped = min(max(page, 1), totalPages)
        if let session = bundleSession, !session.pages.contains(clamped) {
            let spread = MushafSpread.forDisplay(
                containing: clamped,
                totalPages: totalPages,
                allowedPages: session.pages,
                showsSpread: prefersSpreadLayout
            )
            let inSpread = spread.pages.contains { session.pages.contains($0) }
            if !inSpread {
                if isDeckRecordingSession || isActivatingBundle {
                    return
                }
                exitBundleMushaf()
            }
        }
        let identity = MushafSpread.identityPage(
            for: clamped,
            totalPages: totalPages,
            allowedPages: bundleSession?.pages,
            showsSpread: prefersSpreadLayout
        )
        currentPage = identity
        isFireMode = false
        syncBundleIndex(with: identity)
        persistLastPage()
        captureJournalRecordingPages()
        Task {
            await loadSpread(around: identity)
            await prefetchAround(identity)
            if shouldReloadMushafMarks {
                await reloadCoachMarksForVisiblePages()
            }
        }
        publishPageIfListener(identity)
    }

    // MARK: - Block page navigation

    /// Pages that currently have visible blocks (paint + marks, or Feedback filter).
    var visibleBlockPages: Set<Int> {
        var pages: Set<Int>
        if let feedbackBlockPages {
            pages = feedbackBlockPages
        } else if isCoachingFriend {
            // Viewing another user's Mushaf: only their blocks, never local paint.
            pages = Set(markWordPages.values)
        } else {
            pages = []
            if arePaintedWordsVisible {
                pages.formUnion(Set(paintedWordPages.values))
            }
            if areSessionMarksVisible || isViewingFeedbackMarks {
                pages.formUnion(Set(markWordPages.values))
            }
        }
        if let session = bundleSession {
            pages = pages.intersection(Set(session.pages))
        }
        return pages.filter { $0 >= 1 && $0 <= max(totalPages, 1) }
    }

    var previousBlockPage: Int? {
        if let session = bundleSession {
            let pos = deckTraversalIndex(in: session)
            guard pos > 0 else { return nil }
            return session.pages[..<pos].reversed().first { visibleBlockPages.contains($0) }
        }
        let anchor = visiblePageNumbers.min() ?? currentPage
        return visibleBlockPages.sorted().last { $0 < anchor }
    }

    var nextBlockPage: Int? {
        if let session = bundleSession {
            let pos = deckTraversalIndex(in: session)
            guard pos + 1 < session.pages.count else { return nil }
            return session.pages[(pos + 1)...].first { visibleBlockPages.contains($0) }
        }
        let anchor = visiblePageNumbers.max() ?? currentPage
        return visibleBlockPages.sorted().first { $0 > anchor }
    }

    var showsBlockPageNavigation: Bool {
        previousBlockPage != nil || nextBlockPage != nil
    }

    func goToPreviousBlockPage() {
        guard let page = previousBlockPage else { return }
        goToBlockPage(page)
    }

    func goToNextBlockPage() {
        guard let page = nextBlockPage else { return }
        goToBlockPage(page)
    }

    private func deckTraversalIndex(in session: BundleMushafSession) -> Int {
        if let index = session.pages.firstIndex(where: { visiblePageNumbers.contains($0) }) {
            return index
        }
        if let index = session.pages.firstIndex(of: currentPage) {
            return index
        }
        return session.currentIndex
    }

    private func goToBlockPage(_ page: Int) {
        if let session = bundleSession, let index = session.pages.firstIndex(of: page) {
            goToBundlePage(at: index)
        } else {
            goToPage(page, force: true)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setFeedbackBlockPages(_ pages: Set<Int>?) {
        feedbackBlockPages = pages?.isEmpty == true ? nil : pages
    }

    /// Jump to a verse from phonetic search and briefly highlight its words on that page.
    func goToVerse(page: Int, verseKey: String) {
        let targetPage = min(max(page, 1), totalPages)
        verseSearchHighlightClearTask?.cancel()
        verseSearchHighlight = VerseSearchHighlight(page: targetPage, verseKey: verseKey)
        goToPage(targetPage, force: true)

        verseSearchHighlightClearTask = Task {
            await loadPage(targetPage)
            if verseSearchHighlightWordIDs(for: targetPage).isEmpty {
                await forceRefreshPage(targetPage)
            }
            // Ensure pager/content stamp refreshes once ayah-tagged words are available.
            verseSearchHighlightEpoch &+= 1

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if verseSearchHighlight?.page == targetPage, verseSearchHighlight?.verseKey == verseKey {
                verseSearchHighlight = nil
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Jump to a surah's first page and briefly highlight its header (title + bismillah).
    func goToSurah(page: Int, surah: Int) {
        let targetPage = min(max(page, 1), totalPages)
        surahHeaderHighlightClearTask?.cancel()
        surahHeaderHighlight = SurahHeaderHighlight(page: targetPage, surah: surah)
        goToPage(targetPage, force: true)
        surahHeaderHighlightClearTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if surahHeaderHighlight?.page == targetPage, surahHeaderHighlight?.surah == surah {
                surahHeaderHighlight = nil
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func highlightedSurahHeader(for pageNumber: Int) -> Int? {
        guard let highlight = surahHeaderHighlight, highlight.page == pageNumber else { return nil }
        return highlight.surah
    }

    /// Network re-fetch used when cached page lacks ayah tags needed for verse highlight.
    private func forceRefreshPage(_ position: Int) async {
        let fetchMushafID = mushafID
        do {
            let page = try await api.fetchPage(mushafID: fetchMushafID, position: position)
            guard mushafID == fetchMushafID else { return }
            await pageCache.store(page)
            pages[position] = page
            await loadVariationsForPage(page)
            prefetchVerseTranslations(for: page)
        } catch {
            // Keep cached page; highlight may remain empty if ayah tags are unavailable.
        }
    }

    func verseSearchHighlightWordIDs(for pageNumber: Int) -> Set<Int> {
        guard let highlight = verseSearchHighlight,
              highlight.page == pageNumber,
              let page = pages[pageNumber]
        else { return [] }
        return MushafWordVerse.searchHighlightWordIDs(
            on: page,
            pageNumber: pageNumber,
            verseKey: highlight.verseKey,
            mushafID: mushafID
        )
    }

    func onPageChanged(_ page: Int) {
        if isActivatingBundle {
            return
        }
        if isReviewActive, !isReviewListener, !isApplyingRemotePage {
            return
        }
        let identity = MushafSpread.identityPage(
            for: page,
            totalPages: totalPages,
            allowedPages: bundleSession?.pages,
            showsSpread: prefersSpreadLayout
        )
        // Ignore stale reports for pages outside the active deck while it's mounted.
        if let session = bundleSession, !session.pages.contains(identity) {
            let spread = MushafSpread.forDisplay(
                containing: identity,
                totalPages: totalPages,
                allowedPages: session.pages,
                showsSpread: prefersSpreadLayout
            )
            let inSpread = spread.pages.contains { session.pages.contains($0) }
            if !inSpread {
                return
            }
        }
        syncBundleIndex(with: identity)
        currentPage = identity
        isFireMode = false
        if verseSearchHighlight?.page != identity {
            verseSearchHighlight = nil
            verseSearchHighlightClearTask?.cancel()
        }
        persistLastPage()
        captureJournalRecordingPages()
        Task {
            await loadSpread(around: identity)
            await prefetchAround(identity)
            traversalIndex = 0
            activeWordID = nil
            selectedVerse = nil
            verseTranslationTask?.cancel()
            if shouldReloadMushafMarks {
                await reloadCoachMarksForVisiblePages()
            }
        }
        publishPageIfListener(identity)
    }

    func prefetchAround(_ center: Int) async {
        let fetchMushafID = mushafID
        var pagesToPrefetch: [Int] = []

        if prefersSpreadLayout {
            let current = MushafSpread.forDisplay(
                containing: center,
                totalPages: totalPages,
                allowedPages: bundleSession?.pages,
                showsSpread: true
            )
            pagesToPrefetch.append(contentsOf: current.pages.filter { $0 != center })

            if let next = MushafSpread.adjacentIdentity(
                from: current.rightPage,
                forward: true,
                totalPages: totalPages,
                allowedPages: bundleSession?.pages,
                showsSpread: true
            ) {
                pagesToPrefetch.append(contentsOf: MushafSpread.forDisplay(
                    containing: next,
                    totalPages: totalPages,
                    allowedPages: bundleSession?.pages,
                    showsSpread: true
                ).pages)
            }
            if let prev = MushafSpread.adjacentIdentity(
                from: current.rightPage,
                forward: false,
                totalPages: totalPages,
                allowedPages: bundleSession?.pages,
                showsSpread: true
            ) {
                pagesToPrefetch.append(contentsOf: MushafSpread.forDisplay(
                    containing: prev,
                    totalPages: totalPages,
                    allowedPages: bundleSession?.pages,
                    showsSpread: true
                ).pages)
            }
        } else if let session = bundleSession, let centerIndex = session.pages.firstIndex(of: center) {
            pagesToPrefetch = (-2...2)
                .map { centerIndex + $0 }
                .filter { session.pages.indices.contains($0) && session.pages[$0] != center }
                .map { session.pages[$0] }
        } else {
            pagesToPrefetch = (-5...5)
                .filter { $0 != 0 }
                .map { center + $0 }
                .filter { $0 >= 1 && $0 <= totalPages }
        }

        let unique = Array(Set(pagesToPrefetch)).sorted()
        for p in unique {
            guard mushafID == fetchMushafID else { return }
            if let cached = await pageCache.page(p) {
                pages[p] = cached
                continue
            }
            if let page = try? await api.fetchPage(mushafID: fetchMushafID, position: p) {
                guard mushafID == fetchMushafID else { return }
                await pageCache.store(page)
                pages[p] = page
            }
        }
    }

    /// Update landscape spread preference and load partner pages without fighting review locks.
    func setPrefersSpreadLayout(_ enabled: Bool) {
        let wasEnabled = prefersSpreadLayout
        prefersSpreadLayout = enabled
        captureJournalRecordingPages()
        let identity = MushafSpread.identityPage(
            for: currentPage,
            totalPages: totalPages,
            allowedPages: bundleSession?.pages,
            showsSpread: enabled
        )

        if wasEnabled == enabled, identity == currentPage {
            Task {
                await loadSpread(around: identity)
            }
            return
        }

        if isReviewActive, !isReviewListener {
            if currentPage != identity {
                isApplyingRemotePage = true
                currentPage = identity
                syncBundleIndex(with: identity)
                isApplyingRemotePage = false
            }
            Task {
                await loadSpread(around: identity)
                await prefetchAround(identity)
            }
            return
        }

        if currentPage != identity {
            goToPage(identity)
        } else {
            Task {
                await loadSpread(around: identity)
                await prefetchAround(identity)
            }
        }
    }

    private func loadSpread(around identity: Int) async {
        let spread = MushafSpread.forDisplay(
            containing: identity,
            totalPages: totalPages,
            allowedPages: bundleSession?.pages,
            showsSpread: prefersSpreadLayout
        )
        for page in spread.pages {
            await loadPage(page)
        }
    }

    func loadVariationsForPage(_ page: MushafPage) async {
        guard NetworkMonitor.shared.isConnected else { return }
        let wordIDs = page.lines.flatMap { $0.words.map(\.id) }
        guard !wordIDs.isEmpty else { return }
        do {
            let variations = try await api.fetchVariations(wordIDs: wordIDs)
            variationCache.store(variations)
        } catch {
            guard !Self.isCancelled(error), !Self.isTransientNetworkFailure(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshBulkVariations() async {
        let narratorIDs = selectedNarratorIDs.filter { $0 != NarratorCatalog.hafsID }
        guard !narratorIDs.isEmpty else { return }
        do {
            let variations = try await api.fetchVariations(mushafID: mushafID, narratorIDs: narratorIDs)
            variationCache.store(variations)
        } catch {
            guard !Self.isCancelled(error), !Self.isTransientNetworkFailure(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func setMushafID(_ id: Int) async {
        guard id != mushafID else {
            prefs.mushafID = id
            prefs.hasChosenMushaf = true
            return
        }

        isMushafSwitching = true
        hydrationTask?.cancel()
        hydrationGeneration += 1
        hydrationTask = nil
        endHydrationBackgroundTask()
        pages.removeAll()
        variationCache.removeAll()
        await pageCache.setMushaf(id)

        mushafID = id
        prefs.chooseMushaf(id)
        mushafReloadToken = UUID()
        activeWordID = nil
        traversalIndex = 0
        if let saved = prefs.lastPage(forMushaf: id) {
            currentPage = saved
        }
        MushafBookmarkStore.shared.reload(mushafID: id)

        await loadMushafMetadata()
        await loadSegments()
        await loadPage(currentPage)
        await prefetchAround(currentPage)
        await refreshBulkVariations()
        markWordPages = [:]
        paintedWordPages = [:]
        feedbackBlockPages = nil
        if shouldReloadMushafMarks {
            await reloadCoachMarksForVisiblePages()
            await refreshMarkBlockPageIndex()
        }
        isMushafSwitching = false
        resumeMushafHydration()
    }

    private func persistLastPage() {
        // Don't overwrite free-reading position while browsing a deck session.
        guard bundleSession == nil else { return }
        prefs.setLastPage(currentPage, forMushaf: mushafID)
    }

    func resumeMushafHydration(restart: Bool = false) {
        guard NetworkMonitor.shared.isConnected else { return }
        if !restart, hydrationTask != nil { return }

        hydrationTask?.cancel()
        hydrationGeneration += 1
        let generation = hydrationGeneration
        let fetchMushafID = mushafID
        let total = max(totalPages, 1)
        hydrationTask = Task { [weak self] in
            await self?.hydrateMissingPages(mushafID: fetchMushafID, totalPages: total)
            await MainActor.run {
                guard let self, self.hydrationGeneration == generation else { return }
                self.hydrationTask = nil
                self.endHydrationBackgroundTask()
            }
        }
    }

    /// Keep the hydrate queue going for a short time after leaving the app.
    func continueMushafHydrationInBackground() {
        guard hydrationTask != nil else { return }
        endHydrationBackgroundTask()
        hydrationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MushafHydration") { [weak self] in
            self?.hydrationTask?.cancel()
            self?.endHydrationBackgroundTask()
        }
    }

    private func endHydrationBackgroundTask() {
        guard hydrationBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(hydrationBackgroundTask)
        hydrationBackgroundTask = .invalid
    }

    private func hydrateMissingPages(mushafID fetchMushafID: Int, totalPages total: Int) async {
        guard total >= 1 else { return }
        var missing = await pageCache.missingPositions(in: 1...total)
        if let session = bundleSession {
            let deck = Set(session.pages)
            missing.sort { lhs, rhs in
                let lDeck = deck.contains(lhs)
                let rDeck = deck.contains(rhs)
                if lDeck != rDeck { return lDeck && !rDeck }
                return lhs < rhs
            }
        }

        let chunkSize = 2
        var index = 0
        while index < missing.count {
            if Task.isCancelled { return }
            guard NetworkMonitor.shared.isConnected else { return }
            guard mushafID == fetchMushafID else { return }

            let end = min(index + chunkSize, missing.count)
            let batch = Array(missing[index..<end])
            await withTaskGroup(of: Void.self) { group in
                for position in batch {
                    group.addTask { [weak self] in
                        await self?.hydrateOnePage(position, mushafID: fetchMushafID)
                    }
                }
            }
            index = end
        }
    }

    private func hydrateOnePage(_ position: Int, mushafID fetchMushafID: Int) async {
        if await pageCache.hasDiskPage(position) { return }
        do {
            let page = try await api.fetchPage(mushafID: fetchMushafID, position: position)
            guard mushafID == fetchMushafID else { return }
            await pageCache.store(page, intoMemory: false)
        } catch {
            // Best-effort; next resume will retry missing pages.
        }
    }

    func toggleDarkMode(_ value: Bool) {
        isDarkMode = value
        prefs.isMushafDarkMode = value
    }

    func setTajweedMarkingEnabled(_ enabled: Bool) {
        isTajweedMarkingEnabled = enabled
        prefs.isTajweedMarkingEnabled = enabled
        if !enabled, activeMarkType == .tajweed {
            activeMarkType = .mistake
        }
    }

    func setTranslationLanguage(_ language: TranslationLanguage) {
        guard language != translationLanguage else { return }
        translationLanguage = language
        prefs.translationLanguage = language
        verseTranslationCache.removeAll()
        verseTranslationPrefetchTasks.values.forEach { $0.cancel() }
        verseTranslationPrefetchTasks.removeAll()

        if var detail = selectedVerse {
            detail.translation = nil
            detail.isLoadingTranslation = true
            detail.translationError = nil
            selectedVerse = detail
            verseTranslationTask?.cancel()
            verseTranslationTask = Task {
                await loadVerseTranslation(verseKey: detail.verseKey)
            }
        }

        for page in pages.values {
            prefetchVerseTranslations(for: page)
        }
    }

    func toggleNarrator(_ childID: String) {
        if childID == NarratorCatalog.hafsID { return }

        if selectedNarratorIDs.contains(childID) {
            selectedNarratorIDs.removeAll { $0 == childID }
        } else {
            let nonHafs = selectedNarratorIDs.filter { $0 != NarratorCatalog.hafsID }
            if nonHafs.count >= 2 {
                selectedNarratorIDs = [NarratorCatalog.hafsID, childID]
            } else {
                selectedNarratorIDs.append(childID)
            }
        }
        if !selectedNarratorIDs.contains(NarratorCatalog.hafsID) {
            selectedNarratorIDs.insert(NarratorCatalog.hafsID, at: 0)
        }
        prefs.selectedNarratorIDs = selectedNarratorIDs
        Task { await refreshBulkVariations() }
    }

    func variationLookup(wordID: Int) -> (Variation?, String?) {
        for narratorID in selectedNarratorIDs where narratorID != NarratorCatalog.hafsID {
            if let v = variationCache.variation(wordID: wordID, narratorID: narratorID) {
                return (v, findChildColor(narratorID))
            }
        }
        return (nil, nil)
    }

    func isJuzFirstLine(_ linePosition: Int) -> Bool {
        guard let segment = juzSegments.first(where: { currentPage >= $0.startPage && currentPage <= $0.endPage }) else {
            return false
        }
        return currentPage == segment.startPage && linePosition == 1
    }

    func togglePaintMode() {
        guard !isViewingFeedbackMarks else { return }
        guard !isAyahPromptMode else { return }
        isPaintMode.toggle()
        if isPaintMode {
            selectedVerse = nil
            verseTranslationTask?.cancel()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func toggleAyahPromptMode() {
        if isJournalRecording, isAyahPromptMode {
            return
        }
        isAyahPromptMode.toggle()
        if isAyahPromptMode {
            isPaintMode = false
            isMarkingMode = false
            isFireMode = false
            selectedVerse = nil
            verseTranslationTask?.cancel()
            ayahPromptRevealedWordIDs = []
        } else {
            ayahPromptRevealedWordIDs = []
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func toggleJournalRecording() async {
        if isJournalRecording {
            finishJournalRecording()
            return
        }
        let recorder = DeckAudioRecorder.shared
        guard !recorder.isRecording, !isDeckRecordingSession else { return }
        DeckRecordingPlayer.shared.stop()
        enableHelperForJournalRecording()
        let started = await recorder.startJournalSession()
        guard started else {
            errorMessage = recorder.lastError
            return
        }
        isJournalRecording = true
        journalRecordingPages = Set(visiblePageNumbers)
        journalRecordingStartPage = currentPage
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func finishJournalRecording() {
        guard isJournalRecording else { return }
        let pages = journalRecordingPages.sorted()
        let startPage = journalRecordingStartPage
        isJournalRecording = false
        journalRecordingPages = []
        journalRecordingStartPage = nil
        guard let take = DeckAudioRecorder.shared.stopJournalSession() else { return }
        let recording = JournalRecording(
            id: take.id,
            createdAt: take.createdAt,
            duration: take.duration,
            title: DeckRecording.defaultTitle(for: take.createdAt),
            fileName: take.fileName,
            pageNumbers: pages,
            mushafID: mushafID,
            startedPage: startPage
        )
        JournalRecordingStore.shared.save(recording)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func enableHelperForJournalRecording() {
        guard !isAyahPromptMode else { return }
        isAyahPromptMode = true
        isPaintMode = false
        isMarkingMode = false
        isFireMode = false
        selectedVerse = nil
        verseTranslationTask?.cancel()
        ayahPromptRevealedWordIDs = []
    }

    private func captureJournalRecordingPages() {
        guard isJournalRecording else { return }
        journalRecordingPages.formUnion(Set(visiblePageNumbers))
    }

    func revealAyahPromptWord(_ wordID: Int) {
        guard isAyahPromptMode else { return }
        ayahPromptRevealedWordIDs.insert(wordID)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Tap-to-expose in helper mode persists as a mark (or local paint if signed out).
    /// Cue words from the 0/1/2 picker stay visible without being saved until tapped.
    private func toggleHelperBlock(_ word: MushafWord, pageNumber: Int) async {
        if isViewingFeedbackMarks {
            if ayahPromptRevealedWordIDs.contains(word.id) {
                ayahPromptRevealedWordIDs.remove(word.id)
            } else {
                ayahPromptRevealedWordIDs.insert(word.id)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        if AuthService.shared.currentUser != nil {
            await handleCoachMarkTap(word, pageNumber: pageNumber, allowWithoutMarkingMode: true)
            return
        }

        var updated = paintedWords
        if updated[word.id] != nil {
            updated.removeValue(forKey: word.id)
            paintedWordPages.removeValue(forKey: word.id)
        } else {
            updated[word.id] = activePaintStyle
            paintedWordPages[word.id] = pageNumber
        }
        paintedWords = updated
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setAyahPromptCueCount(_ count: Int) {
        let clamped = min(2, max(0, count))
        guard clamped != ayahPromptCueCount else { return }
        ayahPromptCueCount = clamped
        prefs.ayahPromptCueCount = clamped
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Cue words after ayah/header (count from settings) plus words the user has tapped to reveal.
    var ayahPromptVisibleWordIDs: Set<Int> {
        var ids = ayahPromptCueWordIDs
        ids.formUnion(ayahPromptRevealedWordIDs)
        ids.formUnion(Set(sessionMarks.keys))
        ids.formUnion(Set(paintedWords.keys))
        return ids
    }

    private var ayahPromptCueWordIDs: Set<Int> {
        let pages = visiblePageNumbers.compactMap { self.pages[$0] }
        return AyahPromptWords.cueWordIDs(
            onPages: pages,
            mushafID: mushafID,
            cueCount: ayahPromptCueCount
        )
    }

    func togglePaintedWordsVisible() {
        arePaintedWordsVisible.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func toggleSessionMarksVisible() {
        areSessionMarksVisible.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func toggleSessionMarksInverted() {
        isSessionMarksInverted.toggle()
        if isSessionMarksInverted {
            areSessionMarksVisible = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setActivePaintStyle(_ style: WordPaintStyle) {
        guard !isAyahPromptMode else { return }
        activePaintStyle = style
        if isViewingFeedbackMarks {
            // Feedback review: restyle marks only — do not enter paint mode.
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        isPaintMode = true
        selectedVerse = nil
        verseTranslationTask?.cancel()

        if !paintedWords.isEmpty {
            var updated = paintedWords
            for wordID in updated.keys {
                updated[wordID] = style
            }
            paintedWords = updated
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func togglePaintInverted() {
        isPaintInverted.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func clearSelectedVerseRef() {
        selectedVerse = nil
        activeWordID = nil
        verseTranslationTask?.cancel()
    }

    private func openVerseDetail(from word: MushafWord) {
        guard let verseKey = MushafWordVerse.verseKey(from: word.ayah),
              let displayRef = MushafWordVerse.formattedReference(from: word.ayah) else { return }

        verseTranslationTask?.cancel()
        activeWordID = word.id

        if let cached = verseTranslationCache[verseKey] {
            selectedVerse = SelectedVerseDetail(
                displayRef: displayRef,
                verseKey: verseKey,
                translation: cached,
                isLoadingTranslation: false
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        selectedVerse = SelectedVerseDetail(displayRef: displayRef, verseKey: verseKey)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        verseTranslationTask = Task {
            await loadVerseTranslation(verseKey: verseKey)
        }
    }

    private func prefetchVerseTranslations(for page: MushafPage) {
        let position = page.position
        if let existing = verseTranslationPrefetchTasks[position], !existing.isCancelled {
            return
        }
        let keys = verseKeys(on: page)
        let language = translationLanguage
        verseTranslationPrefetchTasks[position] = Task { [weak self] in
            await self?.loadVerseTranslations(keys: keys, language: language)
            self?.verseTranslationPrefetchTasks.removeValue(forKey: position)
        }
    }

    private func verseKeys(on page: MushafPage) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for line in page.lines {
            for word in line.words {
                guard let key = MushafWordVerse.verseKey(from: word.ayah), seen.insert(key).inserted else { continue }
                keys.append(key)
            }
        }
        return keys
    }

    private func loadVerseTranslations(keys: [String], language: TranslationLanguage) async {
        let missing = keys.filter { verseTranslationCache[$0] == nil }
        guard !missing.isEmpty, NetworkMonitor.shared.isConnected else { return }
        do {
            let fetched = try await Task.detached {
                try await VerseTranslationsService().fetch(keys: missing, language: language)
            }.value
            guard !Task.isCancelled else { return }
            for (key, text) in fetched {
                verseTranslationCache[key] = text
            }
        } catch {
            guard !Self.isCancelled(error) else { return }
        }
    }

    private func loadVerseTranslation(verseKey: String) async {
        if let cached = verseTranslationCache[verseKey] {
            applyTranslation(cached, for: verseKey)
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            applyTranslationError("Could not load translation", for: verseKey)
            return
        }

        let language = translationLanguage
        do {
            let fetched = try await Task.detached {
                try await VerseTranslationsService().fetch(keys: [verseKey], language: language)
            }.value
            guard !Task.isCancelled else { return }
            if let text = fetched[verseKey], !text.isEmpty {
                verseTranslationCache[verseKey] = text
                applyTranslation(text, for: verseKey)
                return
            }
            applyTranslationError("Translation not found", for: verseKey)
        } catch {
            guard !Task.isCancelled, !Self.isCancelled(error) else { return }
            applyTranslationError("Could not load translation", for: verseKey)
        }
    }

    private func applyTranslation(_ text: String, for verseKey: String) {
        guard var detail = selectedVerse, detail.verseKey == verseKey else { return }
        detail.translation = text
        detail.isLoadingTranslation = false
        detail.translationError = nil
        selectedVerse = detail
    }

    private func applyTranslationError(_ message: String, for verseKey: String) {
        guard var detail = selectedVerse, detail.verseKey == verseKey else { return }
        detail.isLoadingTranslation = false
        detail.translationError = message
        selectedVerse = detail
    }

    func handleWordTap(_ word: MushafWord, pageNumber: Int? = nil) async {
        if isFireMode {
            await handleFireWordTap(word)
            return
        }

        if isAyahPromptMode {
            if MushafWordVerse.isAyahEndingToken(word, mushafID: mushafID) {
                if MushafWordVerse.verseKey(from: word.ayah) != nil {
                    openVerseDetail(from: word)
                }
                return
            }
            await toggleHelperBlock(word, pageNumber: pageNumber ?? currentPage)
            return
        }

        if isMarkingMode, reviewSession?.role == .listener {
            await handleSessionMarkTap(word, pageNumber: pageNumber ?? currentPage)
            return
        }

        if isCoachingFriend || isSelfMarking {
            await handleCoachMarkTap(word, pageNumber: pageNumber ?? currentPage)
            return
        }

        if isPaintMode {
            guard !isViewingFeedbackMarks else { return }
            var updated = paintedWords
            if updated[word.id] == activePaintStyle {
                updated.removeValue(forKey: word.id)
                paintedWordPages.removeValue(forKey: word.id)
            } else {
                updated[word.id] = activePaintStyle
                paintedWordPages[word.id] = pageNumber ?? currentPage
            }
            paintedWords = updated
            return
        }

        if MushafWordVerse.isAyahEndingToken(word, mushafID: mushafID),
           MushafWordVerse.verseKey(from: word.ayah) != nil {
            openVerseDetail(from: word)
            return
        }
    }

    // MARK: - Range highlight (activate only)

    func beginRangeHighlight(from word: MushafWord) {
        guard allowsRangeHighlight else { return }
        // Only start a range from an unhighlighted / unmarked block.
        if isPaintMode {
            guard paintedWords[word.id] != activePaintStyle else { return }
        } else if isMistakeMarkingActive {
            if sessionMarks[word.id] == activeMarkType {
                Task { await handleFireWordTap(word) }
                return
            }
        } else {
            return
        }
        rangeHighlightAnchorWordID = word.id
        rangeHighlightPreviewIDs = [word.id]
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func updateRangeHighlight(to word: MushafWord) {
        guard let anchorID = rangeHighlightAnchorWordID else { return }
        let ids = wordIDs(from: anchorID, to: word.id)
        rangeHighlightPreviewIDs = ids
    }

    func commitRangeHighlight() async {
        let ids = rangeHighlightPreviewIDs
        let anchorID = rangeHighlightAnchorWordID
        rangeHighlightAnchorWordID = nil
        rangeHighlightPreviewIDs = []
        guard anchorID != nil, !ids.isEmpty else { return }

        if isPaintMode {
            var updated = paintedWords
            for id in ids {
                // Activate only — never clear via drag.
                if updated[id] != activePaintStyle {
                    updated[id] = activePaintStyle
                    paintedWordPages[id] = pageNumberContaining(wordID: id) ?? currentPage
                }
            }
            paintedWords = updated
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        guard isMistakeMarkingActive, isMarkingMode else { return }
        let ordered = orderedWordsForRangeSelection()
        let targets = ordered.filter { ids.contains($0.id) && sessionMarks[$0.id] != activeMarkType }
        for word in targets {
            let pageNumber = pageNumberContaining(wordID: word.id) ?? currentPage
            if isMarkingMode, reviewSession?.role == .listener {
                await handleSessionMarkTap(word, pageNumber: pageNumber)
            } else if isCoachingFriend || isSelfMarking {
                await handleCoachMarkTap(word, pageNumber: pageNumber)
            }
        }
    }

    func cancelRangeHighlight() {
        rangeHighlightAnchorWordID = nil
        rangeHighlightPreviewIDs = []
    }

    private func orderedWordsForRangeSelection() -> [MushafWord] {
        visiblePageNumbers.flatMap { pageNumber -> [MushafWord] in
            guard let page = pages[pageNumber] else { return [] }
            return page.lines
                .sorted { $0.position < $1.position }
                .flatMap(\.words)
                .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private func wordIDs(from startID: Int, to endID: Int) -> Set<Int> {
        let ordered = orderedWordsForRangeSelection()
        guard let start = ordered.firstIndex(where: { $0.id == startID }),
              let end = ordered.firstIndex(where: { $0.id == endID })
        else {
            return [startID, endID]
        }
        let low = min(start, end)
        let high = max(start, end)
        return Set(ordered[low...high].map(\.id))
    }

    private func pageNumberContaining(wordID: Int) -> Int? {
        for pageNumber in visiblePageNumbers {
            guard let page = pages[pageNumber] else { continue }
            if page.lines.contains(where: { line in line.words.contains(where: { $0.id == wordID }) }) {
                return pageNumber
            }
        }
        for (pageNumber, page) in pages {
            if page.lines.contains(where: { line in line.words.contains(where: { $0.id == wordID }) }) {
                return pageNumber
            }
        }
        return nil
    }

    func surahNumber(for word: MushafWord) -> Int? {
        for segment in surahSegments {
            if let n = segment.categoryPosition,
               currentPage >= segment.startPage,
               currentPage <= segment.endPage {
                return n
            }
        }
        return nil
    }

    /// Surah containing a page (for Add to Deck / whole-surah actions).
    func surahSegment(containingPage pageNumber: Int) -> NavigationSegment? {
        surahSegments
            .filter { pageNumber >= $0.startPage && pageNumber <= $0.endPage }
            .sorted { $0.startPage > $1.startPage }
            .first
    }

    func juzSegment(containingPage pageNumber: Int) -> NavigationSegment? {
        juzSegments
            .filter { pageNumber >= $0.startPage && pageNumber <= $0.endPage }
            .sorted { $0.startPage > $1.startPage }
            .first
    }

    /// IndoPak 13-line printed-style header metadata for a page.
    func pageHeaderInfo(for pageNumber: Int) -> MushafPageHeaderInfo? {
        guard mushafID == MushafID.indoPak.rawValue else { return nil }
        guard let surah = surahSegment(containingPage: pageNumber),
              let surahNumber = surah.categoryPosition,
              let juz = juzSegment(containingPage: pageNumber),
              let juzNumber = juz.categoryPosition
        else { return nil }

        let name = SurahMeta.arabicName(surahNumber)
        let resolvedName = name.isEmpty ? surah.title : name
        return MushafPageHeaderInfo(
            surahName: resolvedName,
            surahNumber: surahNumber,
            pageNumber: PrintedPage.display(pageNumber, mushafID: mushafID),
            juzNumber: juzNumber
        )
    }

    func suggestedTitle(for segment: NavigationSegment) -> String {
        if let number = segment.categoryPosition {
            let english = SurahMeta.englishName(number)
            if !english.isEmpty { return english }
            return SurahMeta.arabicName(number)
        }
        return segment.title
    }

    func beginWholeSurahDeck(from segment: NavigationSegment) {
        let low = min(segment.startPage, segment.endPage)
        let high = max(segment.startPage, segment.endPage)
        let pages = Array(low...min(high, totalPages))
        pendingNewDeck = PendingNewDeck(pages: pages, suggestedTitle: suggestedTitle(for: segment))
        deckEndRangeSelection = nil
        isAddToBundleOpen = false
    }

    func beginDeckEndRangeSelection(from segment: NavigationSegment) {
        let start = min(max(currentPage, segment.startPage), segment.endPage)
        deckEndRangeSelection = DeckEndRangeSelection(
            startPage: start,
            suggestedTitle: suggestedTitle(for: segment)
        )
        isAddToBundleOpen = false
    }

    func beginSinglePageDeck() {
        pendingNewDeck = PendingNewDeck(pages: [currentPage], suggestedTitle: nil)
        deckEndRangeSelection = nil
        isAddToBundleOpen = false
    }

    func cancelDeckEndRangeSelection() {
        deckEndRangeSelection = nil
    }

    func finishDeckEndRangeSelection() {
        guard let selection = deckEndRangeSelection else { return }
        let low = min(selection.startPage, currentPage)
        let high = max(selection.startPage, currentPage)
        let pages = Array(low...min(high, totalPages))
        pendingNewDeck = PendingNewDeck(pages: pages, suggestedTitle: selection.suggestedTitle)
        deckEndRangeSelection = nil
    }

    func clearPendingNewDeck() {
        pendingNewDeck = nil
    }

    func playVerseClip(for word: MushafWord, narratorID: String) async {
        guard let slug = NarratorCatalog.recitationSlug(for: narratorID, parents: parentNarrators) else { return }
        do {
            let detail = try await api.fetchWord(id: word.id)
            guard let ayah = detail.ayah, !ayah.isEmpty else { return }
            let lookup = try await api.lookupVerseSegment(verse: ayah, narratorSlug: slug)
            guard let urlString = lookup.audioURL, let url = URL(string: urlString),
                  let start = lookup.startTime, let end = lookup.endTime
            else { return }
            AudioPlayerService.shared.playClip(
                url: url,
                start: start,
                end: end,
                title: lookup.riwayahTitle ?? slug,
                artist: lookup.reciterSlug,
                artworkURL: nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playShubahWord(_ word: MushafWord, surah: Int) {
        guard let segment = ShubahTimestamps.segment(surah: surah, wordText: word.content),
              let url = ShubahTimestamps.audioURL(surah: surah)
        else { return }
        AudioPlayerService.shared.playClip(
            url: url,
            start: segment.start,
            end: segment.end,
            title: "Shu'bah",
            artist: word.content,
            artworkURL: nil
        )
    }

    func selectTraversal(at index: Int) {
        guard traversalItems.indices.contains(index) else { return }
        traversalIndex = index
        activeWordID = traversalItems[index].wordID
    }

    func nextTraversal() {
        guard !traversalItems.isEmpty else { return }
        let next = min(traversalIndex + 1, traversalItems.count - 1)
        selectTraversal(at: next)
    }

    func previousTraversal() {
        guard !traversalItems.isEmpty else { return }
        let prev = max(traversalIndex - 1, 0)
        selectTraversal(at: prev)
    }

    func enterReviewSession(_ context: ReviewSessionContext, bundle: MushafBundle, startingPage: Int) {
        reviewSession = context
        isMarkingMode = context.role == .listener
        isPaintMode = false
        pageHidden = false
        enterBundleMushaf(bundle: bundle, startingPage: startingPage)
        startReviewPollingIfNeeded()
    }

    func endReviewSession() async {
        guard let session = reviewSession else { return }
        do {
            _ = try await ReviewSessionService().end(sessionID: session.sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
        reviewPollTask?.cancel()
        reviewPollTask = nil
        reviewSession = nil
        isMarkingMode = false
        pageHidden = false
        sessionMarks = [:]
        sessionMarkIDs = [:]
        sessionMarkHeatCounts = [:]
        sessionPersistedMushafMarkIDs = [:]
        exitBundleMushaf()
    }

    func toggleMarkingMode() {
        guard isReviewListener || isCoaching else { return }
        isMarkingMode.toggle()
        if !isMarkingMode {
            isFireMode = false
        }
        if isMarkingMode {
            isPaintMode = false
            isAyahPromptMode = false
            selectedVerse = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Bottom-bar entry: start/stop marking your own Mushaf (friend picker is separate).
    func toggleSelfMarkingFromEntry() {
        guard AuthService.shared.currentUser != nil else { return }
        guard !isReviewListener else {
            toggleMarkingMode()
            return
        }
        if isCoachingFriend {
            isMarkingMode.toggle()
            if !isMarkingMode {
                isFireMode = false
            }
            if isMarkingMode {
                isPaintMode = false
                isAyahPromptMode = false
                selectedVerse = nil
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        if isSelfMarking {
            isMarkingMode = false
            isFireMode = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        beginSelfMarking()
    }

    func beginSelfMarking() {
        coachSubject = nil
        isMarkingMode = true
        isPaintMode = false
        isAyahPromptMode = false
        selectedVerse = nil
        Task {
            await reloadCoachMarksForVisiblePages()
            await refreshMarkBlockPageIndex()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func enterCoachMode(subject: HifzworldUser) {
        // Selecting yourself is the same as the default — clear friend override.
        if let me = AuthService.shared.currentUser, subject.id == me.id {
            beginSelfMarking()
            return
        }
        coachSubject = subject
        isMarkingMode = true
        isPaintMode = false
        isAyahPromptMode = false
        selectedVerse = nil
        sessionMarks = [:]
        sessionMarkIDs = [:]
        sessionMarkHeatCounts = [:]
        markWordPages = [:]
        feedbackBlockPages = nil
        Task {
            await reloadCoachMarksForVisiblePages()
            await refreshMarkBlockPageIndex()
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func exitCoachMode() {
        // Leave friend override; keep (or restore) your own marks on the page.
        coachSubject = nil
        isMarkingMode = false
        isFireMode = false
        feedbackBlockPages = nil
        Task {
            await reloadCoachMarksForVisiblePages()
            await refreshMarkBlockPageIndex()
        }
    }

    func openCoachMarks(subject: HifzworldUser, page: Int, marks: [MushafMarkDTO], filteredPages: Set<Int>? = nil) {
        if let me = AuthService.shared.currentUser, subject.id == me.id {
            coachSubject = nil
            isMarkingMode = true
            isPaintMode = false
            applyCoachMarks(marks, subjectID: subject.id)
        } else {
            enterCoachMode(subject: subject)
            applyCoachMarks(marks, subjectID: subject.id)
        }
        for mark in marks where !mark.isUnmarked && mark.mushafID == mushafID {
            markWordPages[mark.wordID] = mark.pageNumber
        }
        setFeedbackBlockPages(filteredPages)
        Task { goToPage(page) }
    }

    func reloadCoachMarksForVisiblePages() async {
        guard let subject = markSubject else { return }
        do {
            var loaded: [MushafMarkDTO] = []
            for page in visiblePageNumbers {
                let pageMarks = try await MushafMarksService().list(
                    subjectID: subject.id,
                    page: page,
                    mushafID: mushafID,
                    limit: 500
                )
                loaded.append(contentsOf: pageMarks)
            }
            applyCoachMarks(loaded, subjectID: subject.id)
            mergeMarkWordPages(from: loaded, replacingPages: Set(visiblePageNumbers), subjectID: subject.id)
        } catch {
            // Offline / unreachable: keep showing locally queued marks.
            applyPendingCoachMarksOnly(subjectID: subject.id)
            if NetworkMonitor.shared.isConnected, !Self.isTransientNetworkFailure(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyCoachMarks(_ marks: [MushafMarkDTO], subjectID: UUID) {
        var types: [Int: MistakeMarkType] = [:]
        var ids: [Int: UUID] = [:]
        var heats: [Int: Int] = [:]
        for mark in marks where mark.mushafID == mushafID && !mark.isUnmarked {
            types[mark.wordID] = MistakeMarkType.resolved(from: mark.markType)
            ids[mark.wordID] = mark.id
            heats[mark.wordID] = mark.heatCount
        }
        // Pending deletes drop server ids; pending upserts overlay types until synced.
        for op in pendingMarks.ops(subjectID: subjectID, mushafID: mushafID) {
            if op.kind == .delete {
                ids.removeValue(forKey: op.wordID)
            }
        }
        types = pendingMarks.overlayTypes(onto: types, subjectID: subjectID, mushafID: mushafID)
        sessionMarks = types
        sessionMarkIDs = ids
        sessionMarkHeatCounts = heats
    }

    func refreshMarkBlockPageIndex() async {
        guard let subject = markSubject else { return }
        do {
            let loaded = try await MushafMarksService().list(
                subjectID: subject.id,
                mushafID: mushafID,
                limit: 500
            )
            seedMarkWordPages(from: loaded, subjectID: subject.id)
        } catch {
            overlayPendingMarkPages(subjectID: subject.id)
        }
    }

    private func seedMarkWordPages(from marks: [MushafMarkDTO], subjectID: UUID) {
        var map: [Int: Int] = [:]
        for mark in marks where mark.mushafID == mushafID && !mark.isUnmarked {
            map[mark.wordID] = mark.pageNumber
        }
        markWordPages = map
        overlayPendingMarkPages(subjectID: subjectID)
    }

    private func mergeMarkWordPages(from marks: [MushafMarkDTO], replacingPages: Set<Int>, subjectID: UUID) {
        markWordPages = markWordPages.filter { !replacingPages.contains($0.value) }
        for mark in marks where mark.mushafID == mushafID && !mark.isUnmarked {
            markWordPages[mark.wordID] = mark.pageNumber
        }
        overlayPendingMarkPages(subjectID: subjectID)
    }

    private func overlayPendingMarkPages(subjectID: UUID) {
        for op in pendingMarks.ops(subjectID: subjectID, mushafID: mushafID).sorted(by: { $0.createdAt < $1.createdAt }) {
            switch op.kind {
            case .upsert:
                markWordPages[op.wordID] = op.pageNumber
            case .delete:
                markWordPages.removeValue(forKey: op.wordID)
            }
        }
    }

    private func syncPaintedWordPagesFromLoadedPages() {
        var map: [Int: Int] = [:]
        for (pageNumber, page) in pages {
            for line in page.lines {
                for word in line.words where paintedWords[word.id] != nil {
                    map[word.id] = pageNumber
                }
            }
        }
        for (wordID, page) in paintedWordPages where paintedWords[wordID] != nil && map[wordID] == nil {
            map[wordID] = page
        }
        paintedWordPages = map
    }

    private func applyPendingCoachMarksOnly(subjectID: UUID) {
        let overlaid = pendingMarks.overlayTypes(
            onto: sessionMarks,
            subjectID: subjectID,
            mushafID: mushafID
        )
        var ids = sessionMarkIDs
        for op in pendingMarks.ops(subjectID: subjectID, mushafID: mushafID) where op.kind == .delete {
            ids.removeValue(forKey: op.wordID)
        }
        sessionMarks = overlaid
        sessionMarkIDs = ids
    }

    private func handleFireWordTap(_ word: MushafWord) async {
        guard sessionMarks[word.id] != nil else {
            isFireMode = false
            return
        }
        let markID: UUID?
        if isReviewListener {
            markID = sessionPersistedMushafMarkIDs[word.id]
        } else {
            markID = sessionMarkIDs[word.id]
        }
        guard let markID else { return }
        do {
            let heat = try await MushafMarksService().createHeat(markID: markID)
            sessionMarkHeatCounts[word.id] = heat.heatsCount ?? (sessionMarkHeatCounts[word.id] ?? 0) + 1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = Self.friendlyMarkAPIError(error)
        }
    }

    private func handleCoachMarkTap(
        _ word: MushafWord,
        pageNumber: Int,
        allowWithoutMarkingMode: Bool = false
    ) async {
        guard let subject = markSubject else {
            errorMessage = "Sign in to mark the Mushaf"
            return
        }
        guard isMarkingMode || allowWithoutMarkingMode else { return }
        guard let page = pages[pageNumber] else {
            errorMessage = "Page not loaded yet"
            return
        }
        let reference = MushafWordVerse.markReference(for: word, on: page, pageNumber: pageNumber)

        if let existingType = sessionMarks[word.id] {
            // Same type → remove; different type → change (both persist to the server).
            if existingType == activeMarkType {
                await removeCoachMark(
                    wordID: word.id,
                    pageNumber: pageNumber,
                    subjectID: subject.id,
                    previousType: existingType,
                    previousID: sessionMarkIDs[word.id]
                )
            } else {
                await upsertCoachMark(
                    word: word,
                    pageNumber: pageNumber,
                    reference: reference,
                    subjectID: subject.id,
                    markType: activeMarkType
                )
            }
            return
        }

        await upsertCoachMark(
            word: word,
            pageNumber: pageNumber,
            reference: reference,
            subjectID: subject.id,
            markType: activeMarkType
        )
    }

    private func removeCoachMark(
        wordID: Int,
        pageNumber: Int,
        subjectID: UUID,
        previousType: MistakeMarkType,
        previousID: UUID?
    ) async {
        var types = sessionMarks
        var ids = sessionMarkIDs
        types.removeValue(forKey: wordID)
        ids.removeValue(forKey: wordID)
        sessionMarks = types
        sessionMarkIDs = ids
        sessionMarkHeatCounts.removeValue(forKey: wordID)
        if types[wordID] == nil {
            markWordPages.removeValue(forKey: wordID)
        }

        let stamped = Date()

        if !NetworkMonitor.shared.isConnected {
            pendingMarks.enqueueDelete(
                subjectID: subjectID,
                wordID: wordID,
                pageNumber: pageNumber,
                mushafID: mushafID,
                serverMarkID: previousID,
                at: stamped
            )
            return
        }

        var markID = previousID
        if markID == nil {
            markID = await resolveCoachMarkID(wordID: wordID, pageNumber: pageNumber, subjectID: subjectID)
        }

        guard let markID else {
            // Never synced — clear any pending upsert.
            pendingMarks.enqueueDelete(
                subjectID: subjectID,
                wordID: wordID,
                pageNumber: pageNumber,
                mushafID: mushafID,
                serverMarkID: nil,
                at: stamped
            )
            return
        }

        do {
            try await MushafMarksService().unmark(id: markID, at: stamped)
            pendingMarks.removeOps(subjectID: subjectID, wordID: wordID, mushafID: mushafID)
        } catch {
            if Self.isTransientNetworkFailure(error) {
                pendingMarks.enqueueDelete(
                    subjectID: subjectID,
                    wordID: wordID,
                    pageNumber: pageNumber,
                    mushafID: mushafID,
                    serverMarkID: markID,
                    at: stamped
                )
            } else {
                var restoredTypes = sessionMarks
                var restoredIDs = sessionMarkIDs
                restoredTypes[wordID] = previousType
                restoredIDs[wordID] = markID
                sessionMarks = restoredTypes
                sessionMarkIDs = restoredIDs
                markWordPages[wordID] = pageNumber
                errorMessage = Self.friendlyMarkAPIError(error)
            }
        }
    }

    private func upsertCoachMark(
        word: MushafWord,
        pageNumber: Int,
        reference: MushafWordVerse.MarkReference,
        subjectID: UUID,
        markType: MistakeMarkType
    ) async {
        let previousType = sessionMarks[word.id]
        let previousID = sessionMarkIDs[word.id]
        let stamped = Date()

        var types = sessionMarks
        types[word.id] = markType
        sessionMarks = types
        markWordPages[word.id] = pageNumber
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if !NetworkMonitor.shared.isConnected {
            pendingMarks.enqueueUpsert(
                subjectID: subjectID,
                wordID: word.id,
                verseKey: reference.verseKey,
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: markType,
                lineNumber: reference.lineNumber,
                wordPosition: reference.wordPosition,
                at: stamped
            )
            return
        }

        do {
            let mark = try await MushafMarksService().create(
                subjectID: subjectID,
                wordID: word.id,
                verseKey: reference.verseKey,
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: markType,
                lineNumber: reference.lineNumber,
                wordPosition: reference.wordPosition
            )
            pendingMarks.removeOps(subjectID: subjectID, wordID: word.id, mushafID: mushafID)
            var nextTypes = sessionMarks
            var nextIDs = sessionMarkIDs
            nextTypes[word.id] = MistakeMarkType.resolved(from: mark.markType)
            nextIDs[word.id] = mark.id
            sessionMarks = nextTypes
            sessionMarkIDs = nextIDs
        } catch {
            if Self.isTransientNetworkFailure(error) {
                pendingMarks.enqueueUpsert(
                    subjectID: subjectID,
                    wordID: word.id,
                    verseKey: reference.verseKey,
                    pageNumber: pageNumber,
                    mushafID: mushafID,
                    markType: markType,
                    lineNumber: reference.lineNumber,
                    wordPosition: reference.wordPosition,
                    at: stamped
                )
            } else {
                var nextTypes = sessionMarks
                var nextIDs = sessionMarkIDs
                if let previousType {
                    nextTypes[word.id] = previousType
                } else {
                    nextTypes.removeValue(forKey: word.id)
                }
                if let previousID {
                    nextIDs[word.id] = previousID
                } else {
                    nextIDs.removeValue(forKey: word.id)
                }
                sessionMarks = nextTypes
                sessionMarkIDs = nextIDs
                errorMessage = Self.friendlyMarkAPIError(error)
            }
        }
    }

    /// Upload locally queued Mushaf marks once the network is usable.
    func flushPendingMushafMarksIfNeeded() async {
        guard !isFlushingPendingMarks else { return }
        guard NetworkMonitor.shared.isConnected else { return }
        guard pendingMarks.hasPending else { return }
        guard AuthService.shared.isSignedIn else { return }

        isFlushingPendingMarks = true
        defer { isFlushingPendingMarks = false }

        let snapshot = pendingMarks.items.sorted { $0.createdAt < $1.createdAt }
        for op in snapshot {
            do {
                switch op.kind {
                case .upsert:
                    let mark = try await MushafMarksService().create(
                        subjectID: op.subjectID,
                        wordID: op.wordID,
                        verseKey: op.verseKey.isEmpty ? "p\(op.pageNumber)" : op.verseKey,
                        pageNumber: op.pageNumber,
                        mushafID: op.mushafID,
                        markType: MistakeMarkType.resolved(from: op.markType),
                        note: op.note,
                        lineNumber: op.lineNumber,
                        wordPosition: op.wordPosition,
                        markedAt: op.createdAt
                    )
                    pendingMarks.remove(id: op.id)
                    if markSubject?.id == op.subjectID, op.mushafID == mushafID {
                        var ids = sessionMarkIDs
                        ids[op.wordID] = mark.id
                        sessionMarkIDs = ids
                        if sessionMarks[op.wordID] == nil {
                            var types = sessionMarks
                            types[op.wordID] = MistakeMarkType.resolved(from: mark.markType)
                            sessionMarks = types
                        }
                    }
                case .delete:
                    var markID = op.serverMarkID
                    if markID == nil {
                        markID = await resolveCoachMarkID(
                            wordID: op.wordID,
                            pageNumber: op.pageNumber,
                            subjectID: op.subjectID
                        )
                    }
                    if let markID {
                        try await MushafMarksService().unmark(id: markID)
                    }
                    pendingMarks.remove(id: op.id)
                }
            } catch {
                if Self.isTransientNetworkFailure(error) {
                    break
                }
                // Drop permanently failing ops so the queue can't stall forever.
                pendingMarks.remove(id: op.id)
            }
        }
    }

    private static func isTransientNetworkFailure(_ error: Error) -> Bool {
        if !NetworkMonitor.shared.isConnected { return true }
        if case APIError.network = error { return true }
        if case APIError.httpStatus(let code, _) = error, (500...599).contains(code) {
            return true
        }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
    }

    private func resolveCoachMarkID(wordID: Int, pageNumber: Int, subjectID: UUID) async -> UUID? {
        do {
            let pageMarks = try await MushafMarksService().list(
                subjectID: subjectID,
                page: pageNumber,
                mushafID: mushafID,
                limit: 500
            )
            return pageMarks.first(where: { $0.wordID == wordID })?.id
        } catch {
            return nil
        }
    }

    private static func friendlyMarkAPIError(_ error: Error) -> String {
        if case APIError.httpStatus(let code, let message) = error {
            if let message, !message.isEmpty { return message }
            if code == 404 {
                return "Marking isn’t available on the server yet. Try again after the API updates."
            }
            return "HTTP error \(code)"
        }
        return error.localizedDescription
    }

    func setActiveMarkType(_ type: MistakeMarkType) {
        isFireMode = false
        guard type != .tajweed || isTajweedMarkingEnabled else {
            activeMarkType = .mistake
            return
        }
        activeMarkType = type
    }

    func toggleFireMode() {
        guard isMarkingMode else { return }
        isFireMode.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func togglePageHidden() {
        guard isReviewListener, let session = reviewSession else { return }
        let next = !pageHidden
        pageHidden = next
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                _ = try await ReviewSessionService().updateState(
                    sessionID: session.sessionID,
                    currentPage: nil,
                    pageHidden: next
                )
            } catch {
                pageHidden = !next
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleSessionMarkTap(_ word: MushafWord, pageNumber: Int) async {
        guard let session = reviewSession else { return }
        guard let page = pages[pageNumber] else {
            errorMessage = "Page not loaded yet"
            return
        }
        let reference = MushafWordVerse.markReference(for: word, on: page, pageNumber: pageNumber)

        if let existingType = sessionMarks[word.id] {
            if existingType == activeMarkType {
                let previousID = sessionMarkIDs[word.id]
                var types = sessionMarks
                var ids = sessionMarkIDs
                types.removeValue(forKey: word.id)
                ids.removeValue(forKey: word.id)
                sessionMarks = types
                sessionMarkIDs = ids
                markWordPages.removeValue(forKey: word.id)
                sessionMarkHeatCounts.removeValue(forKey: word.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                if let markID = previousID {
                    do {
                        try await ReviewSessionService().unmarkMark(id: markID)
                        await deletePersistedLiveReviewMark(for: word.id)
                    } catch {
                        var restoredTypes = sessionMarks
                        var restoredIDs = sessionMarkIDs
                        restoredTypes[word.id] = existingType
                        restoredIDs[word.id] = markID
                        sessionMarks = restoredTypes
                        sessionMarkIDs = restoredIDs
                        markWordPages[word.id] = pageNumber
                        errorMessage = error.localizedDescription
                    }
                }
                return
            }
            // Different type → update in place.
        }

        let previousType = sessionMarks[word.id]
        let previousID = sessionMarkIDs[word.id]
        var pendingTypes = sessionMarks
        pendingTypes[word.id] = activeMarkType
        sessionMarks = pendingTypes
        markWordPages[word.id] = pageNumber
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        do {
            let mark = try await ReviewSessionService().createMark(
                sessionID: session.sessionID,
                wordID: word.id,
                verseKey: reference.verseKey,
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: activeMarkType,
                note: nil,
                lineNumber: reference.lineNumber,
                wordPosition: reference.wordPosition
            )
            var nextTypes = sessionMarks
            var nextIDs = sessionMarkIDs
            nextTypes[word.id] = MistakeMarkType.resolved(from: mark.markType)
            nextIDs[word.id] = mark.id
            sessionMarks = nextTypes
            sessionMarkIDs = nextIDs
            await persistLiveReviewMarkToMushaf(
                word: word,
                pageNumber: pageNumber,
                reference: reference,
                markType: activeMarkType
            )
        } catch {
            var nextTypes = sessionMarks
            var nextIDs = sessionMarkIDs
            if let previousType {
                nextTypes[word.id] = previousType
            } else {
                nextTypes.removeValue(forKey: word.id)
            }
            if let previousID {
                nextIDs[word.id] = previousID
            } else {
                nextIDs.removeValue(forKey: word.id)
            }
            sessionMarks = nextTypes
            sessionMarkIDs = nextIDs
            if nextTypes[word.id] == nil {
                markWordPages.removeValue(forKey: word.id)
            } else {
                markWordPages[word.id] = pageNumber
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Copy live-review marks onto the reciter's Mushaf so they appear in Feedback.
    private func persistLiveReviewMarkToMushaf(
        word: MushafWord,
        pageNumber: Int,
        reference: MushafWordVerse.MarkReference,
        markType: MistakeMarkType
    ) async {
        guard let session = reviewSession else { return }
        do {
            let persisted = try await MushafMarksService().create(
                subjectID: session.reciterID,
                wordID: word.id,
                verseKey: reference.verseKey,
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: markType,
                note: MushafMarkDTO.liveReviewNote,
                lineNumber: reference.lineNumber,
                wordPosition: reference.wordPosition
            )
            sessionPersistedMushafMarkIDs[word.id] = persisted.id
            sessionMarkHeatCounts[word.id] = persisted.heatCount
        } catch {
            if Self.isTransientNetworkFailure(error) {
                pendingMarks.enqueueUpsert(
                    subjectID: session.reciterID,
                    wordID: word.id,
                    verseKey: reference.verseKey,
                    pageNumber: pageNumber,
                    mushafID: mushafID,
                    markType: markType,
                    lineNumber: reference.lineNumber,
                    wordPosition: reference.wordPosition,
                    note: MushafMarkDTO.liveReviewNote,
                    at: Date()
                )
            }
        }
    }

    private func deletePersistedLiveReviewMark(for wordID: Int) async {
        if let mushafMarkID = sessionPersistedMushafMarkIDs.removeValue(forKey: wordID) {
            try? await MushafMarksService().unmark(id: mushafMarkID)
            return
        }
        guard let session = reviewSession else { return }
        pendingMarks.enqueueDelete(
            subjectID: session.reciterID,
            wordID: wordID,
            pageNumber: currentPage,
            mushafID: mushafID,
            serverMarkID: nil
        )
    }

    private func publishPageIfListener(_ page: Int) {
        guard isReviewListener, let session = reviewSession, !isApplyingRemotePage else { return }
        Task {
            do {
                _ = try await ReviewSessionService().updateState(
                    sessionID: session.sessionID,
                    currentPage: page,
                    pageHidden: nil
                )
            } catch {
                // Ignore transient publish errors; next poll/swipe will reconcile.
            }
        }
    }

    private func applyRemotePage(_ page: Int) {
        let identity = MushafSpread.identityPage(
            for: page,
            totalPages: totalPages,
            allowedPages: bundleSession?.pages,
            showsSpread: prefersSpreadLayout
        )
        guard identity != currentPage else {
            // Still load partner if rotating into spread with same identity.
            Task { await loadSpread(around: identity) }
            return
        }
        isApplyingRemotePage = true
        defer { isApplyingRemotePage = false }
        syncBundleIndex(with: identity)
        currentPage = identity
        Task {
            await loadSpread(around: identity)
            await prefetchAround(identity)
        }
    }

    private func startReviewPollingIfNeeded() {
        reviewPollTask?.cancel()
        guard reviewSession != nil else { return }
        reviewPollTask = Task {
            while !Task.isCancelled {
                await refreshReviewSessionState()
                await refreshSessionMarks()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func refreshReviewSessionState() async {
        guard let session = reviewSession else { return }
        do {
            let remote = try await ReviewSessionService().fetchSession(sessionID: session.sessionID)
            if remote.status == "ended" {
                reviewPollTask?.cancel()
                reviewPollTask = nil
                reviewSession = nil
                isMarkingMode = false
                pageHidden = false
                sessionMarks = [:]
                sessionMarkIDs = [:]
                sessionMarkHeatCounts = [:]
                exitBundleMushaf()
                return
            }
            pageHidden = remote.pageHidden ?? false
            if !isReviewListener, let remotePage = remote.currentPage {
                applyRemotePage(remotePage)
            }
        } catch {
            // Ignore transient poll errors during active review.
        }
    }

    private func refreshSessionMarks() async {
        guard let session = reviewSession else { return }
        do {
            let marks = try await ReviewSessionService().fetchMarks(sessionID: session.sessionID)
            var map: [Int: MistakeMarkType] = [:]
            var ids: [Int: UUID] = [:]
            for mark in marks where !mark.isUnmarked {
                map[mark.wordID] = MistakeMarkType.resolved(from: mark.markType)
                ids[mark.wordID] = mark.id
            }
            sessionMarks = map
            sessionMarkIDs = ids
        } catch {
            // Ignore transient poll errors during active review.
        }
    }


    private func findChildTitle(_ id: String) -> String? {
        for parent in parentNarrators {
            if let child = parent.children.first(where: { $0.id == id }) {
                return child.title
            }
        }
        return nil
    }

    private func findChildColor(_ id: String) -> String? {
        for parent in parentNarrators {
            if let child = parent.children.first(where: { $0.id == id }) {
                return child.highlightColor
            }
        }
        return nil
    }
}
