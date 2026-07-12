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

    static func groups(for pages: [Int]) -> [BundlePageGroup] {
        guard !pages.isEmpty else { return [] }

        var result: [BundlePageGroup] = []
        var chunkPages = [pages[0]]
        var chunkStartIndex = 0
        var chunkSurah = surah(for: pages[0])

        for index in 1..<pages.count {
            let page = pages[index]
            let previous = pages[index - 1]
            let surah = surah(for: page)

            let isContinuous = page == previous + 1
            let sameSurah = surah?.categoryPosition == chunkSurah?.categoryPosition

            if isContinuous && sameSurah {
                chunkPages.append(page)
            } else {
                result.append(makeGroup(pages: chunkPages, startIndex: chunkStartIndex, surah: chunkSurah))
                chunkPages = [page]
                chunkStartIndex = index
                chunkSurah = surah
            }
        }

        result.append(makeGroup(pages: chunkPages, startIndex: chunkStartIndex, surah: chunkSurah))
        return result
    }

    static func surahTitle(for page: Int) -> String {
        let segment = surah(for: page)
        return displayTitle(for: segment)
    }

    private static func surah(for page: Int) -> NavigationSegment? {
        surahSegments.first { page >= $0.startPage && page <= $0.endPage }
    }

    private static func makeGroup(
        pages: [Int],
        startIndex: Int,
        surah: NavigationSegment?
    ) -> BundlePageGroup {
        let number = surah?.categoryPosition
        let title = displayTitle(for: surah)
        let subtitle = number.map { SurahMeta.englishName($0) }.flatMap { $0.isEmpty ? nil : $0 }
        return BundlePageGroup(
            id: "\(startIndex)-\(pages.map(String.init).joined(separator: "-"))",
            surahNumber: number,
            surahTitle: title,
            surahSubtitle: subtitle,
            pages: pages,
            startIndex: startIndex
        )
    }

    private static func displayTitle(for surah: NavigationSegment?) -> String {
        guard let surah, let number = surah.categoryPosition else {
            return surah?.title ?? "Unknown Surah"
        }
        let arabic = SurahMeta.arabicName(number)
        return arabic.isEmpty ? surah.title : arabic
    }
}
