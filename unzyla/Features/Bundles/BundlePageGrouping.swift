import Foundation

struct BundlePageGroup: Identifiable {
    let id: String
    let surahNumber: Int?
    let surahTitle: String
    let surahSubtitle: String?
    let pages: [Int]
    let startIndex: Int
}

enum BundlePageGrouping {
    /// Surah page ranges per mushaf; page numbers mean different surahs in each mushaf.
    private static let surahSegmentsByMushaf: [Int: [NavigationSegment]] = {
        let entries = SegmentsLoader.loadBundledSegments()
        return Dictionary(uniqueKeysWithValues: MushafID.allCases.map {
            ($0.rawValue, SegmentsLoader.bundledFallback(mushafID: $0.rawValue, entries: entries).surah)
        })
    }()

    private static func surahSegments(mushafID: Int) -> [NavigationSegment] {
        surahSegmentsByMushaf[mushafID] ?? surahSegmentsByMushaf[MushafID.indoPak.rawValue] ?? []
    }

    static func groups(for pages: [Int], mushafID: Int, surahOverrides: [Int: Int] = [:]) -> [BundlePageGroup] {
        guard !pages.isEmpty else { return [] }

        var result: [BundlePageGroup] = []
        var chunkPages = [pages[0]]
        var chunkStartIndex = 0
        var chunkSurahNumber = resolvedSurahNumber(for: pages[0], mushafID: mushafID, overrides: surahOverrides)

        for index in 1..<pages.count {
            let page = pages[index]
            let surahNumber = resolvedSurahNumber(for: page, mushafID: mushafID, overrides: surahOverrides)

            // Keep pages of the same display surah in one section even when there are gaps.
            if surahNumber == chunkSurahNumber {
                chunkPages.append(page)
            } else {
                result.append(makeGroup(pages: chunkPages, startIndex: chunkStartIndex, surahNumber: chunkSurahNumber, mushafID: mushafID))
                chunkPages = [page]
                chunkStartIndex = index
                chunkSurahNumber = surahNumber
            }
        }

        result.append(makeGroup(pages: chunkPages, startIndex: chunkStartIndex, surahNumber: chunkSurahNumber, mushafID: mushafID))
        return result
    }

    static func surahTitle(for page: Int, mushafID: Int, overrides: [Int: Int] = [:]) -> String {
        displayTitle(forSurahNumber: resolvedSurahNumber(for: page, mushafID: mushafID, overrides: overrides), mushafID: mushafID)
    }

    static func resolvedSurahNumber(for page: Int, mushafID: Int, overrides: [Int: Int] = [:]) -> Int? {
        if let override = overrides[page] {
            return override
        }
        return defaultSurahNumber(for: page, mushafID: mushafID)
    }

    static func defaultSurahNumber(for page: Int, mushafID: Int) -> Int? {
        surah(for: page, mushafID: mushafID)?.categoryPosition
    }

    /// Surahs this page can reasonably appear under (default + previous/next boundary surahs).
    static func groupingCandidates(for page: Int, mushafID: Int) -> [Int] {
        var candidates: [Int] = []
        if let current = defaultSurahNumber(for: page, mushafID: mushafID) {
            candidates.append(current)
        }
        if page > 1, let previous = defaultSurahNumber(for: page - 1, mushafID: mushafID), !candidates.contains(previous) {
            candidates.append(previous)
        }
        if let next = defaultSurahNumber(for: page + 1, mushafID: mushafID), !candidates.contains(next) {
            candidates.append(next)
        }
        return candidates
    }

    static func englishName(forSurahNumber number: Int) -> String {
        let name = SurahMeta.englishName(number)
        return name.isEmpty ? "Surah \(number)" : name
    }

    /// Every surah with text on the page, in mushaf order.
    static func surahNumbers(onPage page: Int, mushafID: Int) -> [Int] {
        surahSegments(mushafID: mushafID)
            .filter { page >= $0.startPage && page <= $0.endPage }
            .compactMap(\.categoryPosition)
            .sorted()
    }

    /// The surah the page belongs to: on a page shared by several surahs, the last one to start there.
    private static func surah(for page: Int, mushafID: Int) -> NavigationSegment? {
        surahSegments(mushafID: mushafID)
            .filter { page >= $0.startPage && page <= $0.endPage }
            .max { ($0.startPage, $0.categoryPosition ?? 0) < ($1.startPage, $1.categoryPosition ?? 0) }
    }

    private static func makeGroup(
        pages: [Int],
        startIndex: Int,
        surahNumber: Int?,
        mushafID: Int
    ) -> BundlePageGroup {
        let title = displayTitle(forSurahNumber: surahNumber, mushafID: mushafID)
        let subtitle: String?
        if let surahNumber {
            let name = englishName(forSurahNumber: surahNumber)
            subtitle = name.isEmpty ? nil : name
        } else {
            subtitle = nil
        }
        return BundlePageGroup(
            id: "\(startIndex)-\(pages.map(String.init).joined(separator: "-"))",
            surahNumber: surahNumber,
            surahTitle: title,
            surahSubtitle: subtitle,
            pages: pages,
            startIndex: startIndex
        )
    }

    private static func displayTitle(forSurahNumber number: Int?, mushafID: Int) -> String {
        guard let number else { return "Unknown Surah" }
        let arabic = SurahMeta.arabicName(number)
        if !arabic.isEmpty { return arabic }
        if let segment = surahSegments(mushafID: mushafID).first(where: { $0.categoryPosition == number }) {
            return segment.title
        }
        return "Surah \(number)"
    }
}
