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

    var activeWordID: Int?
    var selectedVerse: SelectedVerseDetail?
    var traversalIndex = 0

    var isPaintMode = false
    var activePaintStyle: WordPaintStyle = .highlight
    var paintedWords: [Int: WordPaintStyle] = [:]
    var arePaintedWordsVisible = true
    var isPaintInverted = false
    /// Prior paint canvas stashed while a deck recording is in progress.
    private var recordingPaintSnapshot: [Int: WordPaintStyle]?
    private(set) var isDeckRecordingSession = false
    /// Prior paint canvas stashed while reviewing a saved take's marks.
    private var reviewPaintSnapshot: [Int: WordPaintStyle]?
    private(set) var isReviewingDeckRecording = false

    var reviewSession: ReviewSessionContext?
    var isMarkingMode = false
    var activeMarkType: MistakeMarkType = .tajweed
    var sessionMarks: [Int: MistakeMarkType] = [:]
    var sessionMarkIDs: [Int: UUID] = [:]
    /// Past feedback review: show listener marks on the deck Mushaf (read-only).
    var isViewingFeedbackMarks = false
    var pageHidden = false
    /// When true (landscape), navigation uses odd-right / even-left spreads.
    var prefersSpreadLayout = false
    private var reviewPollTask: Task<Void, Never>?
    private var isApplyingRemotePage = false
    /// Ignores stale pager callbacks while swapping from one active deck to another.
    private var isActivatingBundle = false

    var isReviewListener: Bool { reviewSession?.role == .listener }
    var isReviewActive: Bool { reviewSession != nil }
    var isReviewPagingEnabled: Bool { !isReviewActive || isReviewListener }

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
        guard isReviewActive, !isReviewListener else { return paintedWords }
        var map = paintedWords
        for wordID in sessionMarks.keys {
            map[wordID] = .blackout
        }
        return map
    }

    /// Whether feedback marks (or paints) exist on the currently visible page(s).
    var hasFeedbackMarksOnVisiblePages: Bool {
        guard isViewingFeedbackMarks, !sessionMarks.isEmpty else { return false }
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

    var iosUpdateWall: MinVersionCheckResult?

    var bundleSession: BundleMushafSession?

    var isBundleMushafMode: Bool { bundleSession != nil }

    private let bundledSegments = SegmentsLoader.loadBundledSegments()
    private var pageLoadTasks: [Int: Task<Void, Never>] = [:]
    private var verseTranslationTask: Task<Void, Never>?
    private var verseTranslationCache: [String: String] = [:]

    private static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    init() {
        mushafID = prefs.mushafID
        isDarkMode = prefs.isMushafDarkMode
        selectedNarratorIDs = prefs.selectedNarratorIDs
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
        isLoading = false
        NowPlayingController.shared.wire(to: AudioPlayerService.shared)
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
            errorMessage = error.localizedDescription
        }
    }

    func loadMushafMetadata() async {
        do {
            let info = try await api.fetchMushaf(id: mushafID)
            if let total = info.totalPages { totalPages = total }
            await pageCache.setMushaf(mushafID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSegments() async {
        if mushafID == MushafID.indoPak.rawValue {
            do {
                let juz = try await api.fetchSegments(mushafID: mushafID, category: "juz")
                let surah = try await api.fetchSegments(mushafID: mushafID, category: "surah")
                juzSegments = SegmentsLoader.fromAPI(juz)
                surahSegments = SegmentsLoader.fromAPI(surah)
            } catch {
                juzSegments = SegmentsLoader.juzSegments(from: bundledSegments)
                surahSegments = SegmentsLoader.surahSegments(from: bundledSegments)
            }
        } else {
            juzSegments = SegmentsLoader.juzSegments(from: bundledSegments)
            surahSegments = SegmentsLoader.surahSegments(from: bundledSegments)
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
            return
        }
        do {
            let page = try await api.fetchPage(mushafID: fetchMushafID, position: position)
            guard mushafID == fetchMushafID else { return }
            await pageCache.store(page)
            pages[position] = page
            await loadVariationsForPage(page)
        } catch {
            guard !Self.isCancelled(error) else { return }
            errorMessage = error.localizedDescription
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
        arePaintedWordsVisible = true
        isPaintMode = false
        isPaintInverted = false
    }

    /// Hides take marks when the deck review session ends; restores personal paints.
    func clearDeckRecordingReviewMarks() {
        guard isReviewingDeckRecording else { return }
        paintedWords = reviewPaintSnapshot ?? [:]
        reviewPaintSnapshot = nil
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

        #if DEBUG
        if session.id == FeedbackSessionDTO.stubPreviewID {
            sessionMarks = Self.previewFeedbackMarks(from: pages, pageNumbers: bundle.pageNumbers)
        } else {
            sessionMarks = Self.sessionMarkMap(from: session.marks)
        }
        #else
        sessionMarks = Self.sessionMarkMap(from: session.marks)
        #endif
        isViewingFeedbackMarks = true

        if let first = session.marks.sorted(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }).first {
            #if DEBUG
            if session.id == FeedbackSessionDTO.stubPreviewID {
                activeWordID = sessionMarks.keys.sorted().first
            } else {
                activeWordID = first.wordID
            }
            #else
            activeWordID = first.wordID
            #endif
            if bundle.pageNumbers.contains(first.pageNumber) {
                goToPage(first.pageNumber, force: true)
            }
        }
    }

    func clearFeedbackReviewMarks() {
        guard isViewingFeedbackMarks else { return }
        sessionMarks = [:]
        sessionMarkIDs = [:]
        isViewingFeedbackMarks = false
        activeWordID = nil
    }

    private static func sessionMarkMap(from marks: [SessionMarkDTO]) -> [Int: MistakeMarkType] {
        var map: [Int: MistakeMarkType] = [:]
        for mark in marks {
            map[mark.wordID] = MistakeMarkType(rawValue: mark.markType) ?? .other
        }
        return map
    }

    #if DEBUG
    private static func previewFeedbackMarks(
        from pages: [Int: MushafPage],
        pageNumbers: [Int]
    ) -> [Int: MistakeMarkType] {
        let types: [MistakeMarkType] = [.tajweed, .hesitation, .pronunciation]
        var map: [Int: MistakeMarkType] = [:]
        var index = 0
        for pageNumber in pageNumbers {
            guard let page = pages[pageNumber], index < types.count else { continue }
            for word in page.lines.flatMap(\.words).prefix(2) {
                guard index < types.count else { break }
                map[word.id] = types[index]
                index += 1
            }
        }
        return map
    }
    #endif

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
        syncBundleIndex(with: identity)
        Task {
            await loadSpread(around: identity)
            await prefetchAround(identity)
        }
        publishPageIfListener(identity)
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
        Task {
            await loadSpread(around: identity)
            await prefetchAround(identity)
            traversalIndex = 0
            activeWordID = nil
            selectedVerse = nil
            verseTranslationTask?.cancel()
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
            if await pageCache.page(p) != nil { continue }
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
        let wordIDs = page.lines.flatMap { $0.words.map(\.id) }
        guard !wordIDs.isEmpty else { return }
        do {
            let variations = try await api.fetchVariations(wordIDs: wordIDs)
            variationCache.store(variations)
        } catch {
            guard !Self.isCancelled(error) else { return }
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
            guard !Self.isCancelled(error) else { return }
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
        pages.removeAll()
        variationCache.removeAll()
        await pageCache.setMushaf(id)

        mushafID = id
        prefs.chooseMushaf(id)
        mushafReloadToken = UUID()
        activeWordID = nil
        traversalIndex = 0

        await loadMushafMetadata()
        await loadSegments()
        await loadPage(currentPage)
        await prefetchAround(currentPage)
        await refreshBulkVariations()
        isMushafSwitching = false
    }

    func toggleDarkMode(_ value: Bool) {
        isDarkMode = value
        prefs.isMushafDarkMode = value
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
        isPaintMode.toggle()
        if isPaintMode {
            selectedVerse = nil
            verseTranslationTask?.cancel()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func togglePaintedWordsVisible() {
        arePaintedWordsVisible.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setActivePaintStyle(_ style: WordPaintStyle) {
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

    private func loadVerseTranslation(verseKey: String) async {
        do {
            let result = try await RevelationClient.search(verseKey: verseKey)
            guard !Task.isCancelled else { return }
            guard var detail = selectedVerse, detail.verseKey == verseKey else { return }

            if let text = result?.translation?.preferredText {
                verseTranslationCache[verseKey] = text
                detail.translation = text
                detail.isLoadingTranslation = false
                detail.translationError = nil
            } else {
                detail.isLoadingTranslation = false
                detail.translationError = "Translation not found"
            }
            selectedVerse = detail
        } catch {
            guard !Task.isCancelled else { return }
            guard var detail = selectedVerse, detail.verseKey == verseKey else { return }
            detail.isLoadingTranslation = false
            detail.translationError = "Could not load translation"
            selectedVerse = detail
        }
    }

    func handleWordTap(_ word: MushafWord, pageNumber: Int? = nil) async {
        if isMarkingMode, reviewSession?.role == .listener {
            await handleSessionMarkTap(word, pageNumber: pageNumber ?? currentPage)
            return
        }

        if isPaintMode {
            guard !isViewingFeedbackMarks else { return }
            var updated = paintedWords
            if updated[word.id] == activePaintStyle {
                updated.removeValue(forKey: word.id)
            } else {
                updated[word.id] = activePaintStyle
            }
            paintedWords = updated
            return
        }

        if MushafWordVerse.isAyahEndingToken(word, mushafID: mushafID),
           MushafWordVerse.verseKey(from: word.ayah) != nil {
            openVerseDetail(from: word)
            return
        }

        activeWordID = word.id
        selectedVerse = nil
        verseTranslationTask?.cancel()
        guard let narratorID = comparisonNarratorID else { return }

        if narratorID == "2" || findChildTitle(narratorID)?.lowercased().contains("shubah") == true {
            let surah = surahNumber(for: word) ?? 1
            playShubahWord(word, surah: surah)
            return
        }

        if variationCache.variation(wordID: word.id, narratorID: narratorID) != nil {
            await playVerseClip(for: word, narratorID: narratorID)
        }
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
        exitBundleMushaf()
    }

    func toggleMarkingMode() {
        guard isReviewListener else { return }
        isMarkingMode.toggle()
        if isMarkingMode {
            isPaintMode = false
            selectedVerse = nil
        }
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

    func setActiveMarkType(_ type: MistakeMarkType) {
        activeMarkType = type
    }

    private func handleSessionMarkTap(_ word: MushafWord, pageNumber: Int) async {
        guard let session = reviewSession else { return }
        guard let verseKey = MushafWordVerse.verseKey(from: word.ayah) else {
            errorMessage = "Could not resolve verse for this word"
            return
        }

        if sessionMarks[word.id] != nil {
            if let markID = sessionMarkIDs[word.id] {
                do {
                    try await ReviewSessionService().deleteMark(id: markID)
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
            sessionMarks.removeValue(forKey: word.id)
            sessionMarkIDs.removeValue(forKey: word.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        do {
            let mark = try await ReviewSessionService().createMark(
                sessionID: session.sessionID,
                wordID: word.id,
                verseKey: verseKey,
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: activeMarkType,
                note: nil
            )
            sessionMarks[word.id] = MistakeMarkType(rawValue: mark.markType) ?? activeMarkType
            sessionMarkIDs[word.id] = mark.id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            for mark in marks {
                map[mark.wordID] = MistakeMarkType(rawValue: mark.markType) ?? .other
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
