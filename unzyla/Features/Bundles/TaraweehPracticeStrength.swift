import Foundation

enum TaraweehPracticeStrength {
    /// 0 = untouched, 4 = strongly practiced with few weak spots.
    static func levels(
        nights: [TaraweehNightPortion],
        marks: [MushafMarkDTO],
        journalRecordings: [JournalRecording],
        deckPageHits: [Set<Int>]
    ) -> [Int: Int] {
        let activeMarks = marks.filter { !$0.isUnmarked && !$0.wasUnmarkedWithinAMinute }

        var marksByPage: [Int: [MushafMarkDTO]] = [:]
        for mark in activeMarks {
            marksByPage[mark.pageNumber, default: []].append(mark)
        }

        var recordedPages = Set<Int>()
        for recording in journalRecordings {
            recordedPages.formUnion(recording.pageNumbers)
        }
        for pages in deckPageHits {
            recordedPages.formUnion(pages)
        }

        var result: [Int: Int] = [:]
        for night in nights {
            let pages = Set(night.pages)
            guard !pages.isEmpty else {
                result[night.night] = 0
                continue
            }

            let covered = pages.intersection(recordedPages)
            let coverage = Double(covered.count) / Double(pages.count)

            var markCount = 0
            var heatSum = 0
            for page in pages {
                let pageMarks = marksByPage[page] ?? []
                markCount += pageMarks.count
                heatSum += pageMarks.reduce(0) { $0 + $1.heatCount }
            }
            let pagesWithMarks = pages.filter { !(marksByPage[$0] ?? []).isEmpty }.count
            let markDensity = Double(pagesWithMarks) / Double(pages.count)
            let avgHeat = markCount > 0 ? Double(heatSum) / Double(markCount) : 0

            result[night.night] = level(
                coverage: coverage,
                markDensity: markDensity,
                avgHeat: avgHeat,
                hasAnySignal: !covered.isEmpty || markCount > 0
            )
        }
        return result
    }

    private static func level(
        coverage: Double,
        markDensity: Double,
        avgHeat: Double,
        hasAnySignal: Bool
    ) -> Int {
        guard hasAnySignal else { return 0 }

        var score: Double
        switch coverage {
        case 0:
            score = markDensity > 0 ? 1.0 : 0
        case ..<0.25:
            score = 1.5
        case ..<0.5:
            score = 2.5
        case ..<0.75:
            score = 3.2
        default:
            score = 4.0
        }

        score -= markDensity * 1.4
        score -= min(2.0, avgHeat / 3.0)

        if coverage == 0, markDensity > 0 {
            score = min(score, 2.0)
        }

        let rounded = Int(score.rounded())
        return min(4, max(1, rounded))
    }
}
