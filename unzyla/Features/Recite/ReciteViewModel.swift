import Foundation
import Observation
import UIKit

struct BundleMushafSession: Equatable {
    let bundleID: UUID
    let title: String
    let pages: [Int]
    var currentIndex: Int

    var groups: [BundlePageGroup] {
        BundlePageGrouping.groups(for: pages)
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
    var activePaintStyle: WordPaintStyle = .blackout
    var paintedWords: [Int: WordPaintStyle] = [:]
    var arePaintedWordsVisible = true
    var isPaintInverted = false

    var reviewSession: ReviewSessionContext?
    var isMarkingMode = false
    var activeMarkType: MistakeMarkType = .tajweed
    var sessionMarks: [Int: MistakeMarkType] = [:]

    var isReviewListener: Bool { reviewSession?.role == .listener }
    var isReviewActive: Bool { reviewSession != nil }

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
        let index = bundle.pageNumbers.firstIndex(of: startingPage) ?? 0
        bundleSession = BundleMushafSession(
            bundleID: bundle.id,
            title: bundle.title,
            pages: bundle.pageNumbers,
            currentIndex: index
        )
        goToPage(bundle.pageNumbers[index])
    }

    func exitBundleMushaf() {
        bundleSession = nil
    }

    func goToBundlePage(at index: Int) {
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
        } else {
            exitBundleMushaf()
        }
    }

    func goToPage(_ page: Int) {
        let clamped = min(max(page, 1), totalPages)
        if let session = bundleSession, !session.pages.contains(clamped) {
            exitBundleMushaf()
        }
        currentPage = clamped
        Task {
            await loadPage(clamped)
            await prefetchAround(clamped)
        }
    }

    func onPageChanged(_ page: Int) {
        syncBundleIndex(with: page)
        currentPage = page
        Task {
            await loadPage(page)
            await prefetchAround(page)
            traversalIndex = 0
            activeWordID = nil
            selectedVerse = nil
            verseTranslationTask?.cancel()
        }
    }

    func prefetchAround(_ center: Int) async {
        let fetchMushafID = mushafID
        let pagesToPrefetch: [Int]

        if let session = bundleSession, let centerIndex = session.pages.firstIndex(of: center) {
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

        for p in pagesToPrefetch {
            guard mushafID == fetchMushafID else { return }
            if await pageCache.page(p) != nil { continue }
            if let page = try? await api.fetchPage(mushafID: fetchMushafID, position: p) {
                guard mushafID == fetchMushafID else { return }
                await pageCache.store(page)
                pages[p] = page
            }
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
        guard id != mushafID else { return }

        isMushafSwitching = true
        pages.removeAll()
        variationCache.removeAll()
        await pageCache.setMushaf(id)

        mushafID = id
        prefs.mushafID = id
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

    func handleWordTap(_ word: MushafWord) async {
        if isMarkingMode, reviewSession?.role == .listener {
            await handleSessionMarkTap(word)
            return
        }

        if isPaintMode {
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
        enterBundleMushaf(bundle: bundle, startingPage: startingPage)
        if let url = context.livekitURL, let token = context.livekitToken, !url.isEmpty, !token.isEmpty {
            Task { await VideoCallService.shared.connect(url: url, token: token) }
        }
    }

    func endReviewSession() async {
        guard let session = reviewSession else { return }
        do {
            _ = try await ReviewSessionService().end(sessionID: session.sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
        reviewSession = nil
        isMarkingMode = false
        sessionMarks = [:]
        await VideoCallService.shared.disconnect()
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

    func setActiveMarkType(_ type: MistakeMarkType) {
        activeMarkType = type
    }

    private func handleSessionMarkTap(_ word: MushafWord) async {
        guard let session = reviewSession else { return }
        guard let verseKey = MushafWordVerse.verseKey(from: word.ayah) else {
            errorMessage = "Could not resolve verse for this word"
            return
        }

        if sessionMarks[word.id] == activeMarkType {
            sessionMarks.removeValue(forKey: word.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        do {
            let mark = try await ReviewSessionService().createMark(
                sessionID: session.sessionID,
                wordID: word.id,
                verseKey: verseKey,
                pageNumber: currentPage,
                mushafID: mushafID,
                markType: activeMarkType,
                note: nil
            )
            sessionMarks[word.id] = MistakeMarkType(rawValue: mark.markType) ?? activeMarkType
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
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
