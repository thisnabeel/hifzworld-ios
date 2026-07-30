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
    private static let surahSegments: [NavigationSegment] = {
        SegmentsLoader.surahSegments(from: SegmentsLoader.loadBundledSegments())
    }()

    static func groups(for pages: [Int], surahOverrides: [Int: Int] = [:]) -> [BundlePageGroup] {
        guard !pages.isEmpty else { return [] }

        var result: [BundlePageGroup] = []
        var chunkPages = [pages[0]]
        var chunkStartIndex = 0
        var chunkSurahNumber = resolvedSurahNumber(for: pages[0], overrides: surahOverrides)

        for index in 1..<pages.count {
            let page = pages[index]
            let surahNumber = resolvedSurahNumber(for: page, overrides: surahOverrides)

            // Keep pages of the same display surah in one section even when there are gaps.
            if surahNumber == chunkSurahNumber {
                chunkPages.append(page)
            } else {
                result.append(makeGroup(pages: chunkPages, startIndex: chunkStartIndex, surahNumber: chunkSurahNumber))
                chunkPages = [page]
                chunkStartIndex = index
                chunkSurahNumber = surahNumber
            }
        }

        result.append(makeGroup(pages: chunkPages, startIndex: chunkStartIndex, surahNumber: chunkSurahNumber))
        return result
    }

    static func surahTitle(for page: Int, overrides: [Int: Int] = [:]) -> String {
        displayTitle(forSurahNumber: resolvedSurahNumber(for: page, overrides: overrides))
    }

    static func resolvedSurahNumber(for page: Int, overrides: [Int: Int]) -> Int? {
        if let override = overrides[page] {
            return override
        }
        return defaultSurahNumber(for: page)
    }

    static func defaultSurahNumber(for page: Int) -> Int? {
        surah(for: page)?.categoryPosition
    }

    /// Surahs this page can reasonably appear under (default + previous/next boundary surahs).
    static func groupingCandidates(for page: Int) -> [Int] {
        var candidates: [Int] = []
        if let current = defaultSurahNumber(for: page) {
            candidates.append(current)
        }
        if page > 1, let previous = defaultSurahNumber(for: page - 1), !candidates.contains(previous) {
            candidates.append(previous)
        }
        if let next = defaultSurahNumber(for: page + 1), !candidates.contains(next) {
            candidates.append(next)
        }
        return candidates
    }

    static func englishName(forSurahNumber number: Int) -> String {
        let name = SurahMeta.englishName(number)
        return name.isEmpty ? "Surah \(number)" : name
    }

    private static func surah(for page: Int) -> NavigationSegment? {
        surahSegments.first { page >= $0.startPage && page <= $0.endPage }
    }

    private static func makeGroup(
        pages: [Int],
        startIndex: Int,
        surahNumber: Int?
    ) -> BundlePageGroup {
        let title = displayTitle(forSurahNumber: surahNumber)
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

    private static func displayTitle(forSurahNumber number: Int?) -> String {
        guard let number else { return "Unknown Surah" }
        let arabic = SurahMeta.arabicName(number)
        if !arabic.isEmpty { return arabic }
        if let segment = surahSegments.first(where: { $0.categoryPosition == number }) {
            return segment.title
        }
        return "Surah \(number)"
    }
}
