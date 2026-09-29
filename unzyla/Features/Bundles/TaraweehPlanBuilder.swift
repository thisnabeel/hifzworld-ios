import Foundation

struct TaraweehRubSpan: Hashable {
    let juzNumber: Int
    let rubIndex: Int // 0...3 within the juz
    let startPage: Int
    let endPage: Int

    var pages: [Int] { Array(startPage...endPage) }
}

struct TaraweehNightPortion: Identifiable, Hashable {
    let night: Int
    let rubUnits: Int
    let startPage: Int
    let endPage: Int
    let pages: [Int]
    /// e.g. "Juz 5"
    let rangeStartLabel: String
    /// e.g. "Juz 6¼"
    let rangeEndLabel: String

    var id: Int { night }

    var portionLabel: String {
        TaraweehPlanBuilder.juzLabel(units: rubUnits)
    }

    /// Mushaf range for accessibility, e.g. "Juz 5 – Juz 6¼".
    var cardJuzLabel: String {
        if rangeStartLabel == rangeEndLabel {
            return rangeStartLabel
        }
        return "\(rangeStartLabel) – \(rangeEndLabel)"
    }

    var cardStartBare: String {
        Self.bareJuzPosition(rangeStartLabel)
    }

    var cardEndBare: String {
        Self.bareJuzPosition(rangeEndLabel)
    }

    /// One-line card range without repeating "Juz", e.g. "1 – 2¼".
    var cardRangeOneLine: String {
        if showsDistinctEnd {
            return "\(cardStartBare) – \(cardEndBare)"
        }
        return cardStartBare
    }

    var showsDistinctEnd: Bool {
        rangeStartLabel != rangeEndLabel
    }

    var pagesLabel: String {
        guard startPage > 0, endPage > 0 else { return "" }
        if startPage == endPage { return "p. \(startPage)" }
        return "p. \(startPage)–\(endPage)"
    }

    private static func bareJuzPosition(_ label: String) -> String {
        if label.hasPrefix("Juz ") {
            return String(label.dropFirst(4))
        }
        return label
    }
}

enum TaraweehPlanBuilder {
    static let totalRubUnits = 30 * 4 // 120

    /// Split each juz into 4 contiguous rub' page spans (last rub' absorbs remainder).
    static func rubSpans(from juzSegments: [NavigationSegment]) -> [TaraweehRubSpan] {
        let ordered = juzSegments.sorted {
            let lhs = $0.categoryPosition ?? $0.startPage
            let rhs = $1.categoryPosition ?? $1.startPage
            return lhs < rhs
        }
        var spans: [TaraweehRubSpan] = []
        for (index, juz) in ordered.enumerated() {
            let juzNumber = juz.categoryPosition ?? (index + 1)
            let start = juz.startPage
            let end = max(juz.startPage, juz.endPage)
            let pageCount = end - start + 1
            let base = pageCount / 4
            let rem = pageCount % 4
            var cursor = start
            for rub in 0..<4 {
                let count = base + (rub < rem ? 1 : 0)
                let rubStart = min(cursor, end)
                let rubEnd: Int
                if count <= 0 {
                    rubEnd = rubStart
                } else {
                    rubEnd = min(end, rubStart + count - 1)
                    cursor = rubEnd + 1
                }
                spans.append(
                    TaraweehRubSpan(
                        juzNumber: juzNumber,
                        rubIndex: rub,
                        startPage: rubStart,
                        endPage: max(rubStart, rubEnd)
                    )
                )
            }
        }
        // Ensure we have exactly 120 when 30 juz present; if short, pad last.
        while spans.count < totalRubUnits, let last = spans.last {
            spans.append(
                TaraweehRubSpan(
                    juzNumber: last.juzNumber,
                    rubIndex: last.rubIndex,
                    startPage: last.endPage,
                    endPage: last.endPage
                )
            )
        }
        if spans.count > totalRubUnits {
            spans = Array(spans.prefix(totalRubUnits))
        }
        return spans
    }

    static func nights(
        finishNight: Int,
        juzSegments: [NavigationSegment]
    ) -> [TaraweehNightPortion] {
        let n = TaraweehPlan.clampedFinishNight(finishNight)
        let spans = rubSpans(from: juzSegments)
        guard !spans.isEmpty else { return [] }

        let base = totalRubUnits / n
        let remainder = totalRubUnits % n

        var result: [TaraweehNightPortion] = []
        var offset = 0
        for night in 1...n {
            let units = base + (night <= remainder ? 1 : 0)
            let slice = Array(spans[offset..<min(offset + units, spans.count)])
            offset += units
            guard let first = slice.first, let last = slice.last else { continue }
            let pages = slice.flatMap(\.pages)
            let uniquePages = Array(Set(pages)).sorted()
            result.append(
                TaraweehNightPortion(
                    night: night,
                    rubUnits: units,
                    startPage: first.startPage,
                    endPage: last.endPage,
                    pages: uniquePages,
                    rangeStartLabel: juzPositionLabel(juz: first.juzNumber, completedRubs: first.rubIndex),
                    rangeEndLabel: juzPositionLabel(juz: last.juzNumber, completedRubs: last.rubIndex + 1)
                )
            )
        }
        return result
    }

    /// Position in the mushaf after `completedRubs` quarters of `juz` (0 = start of that juz, 4 = end of that juz).
    static func juzPositionLabel(juz: Int, completedRubs: Int) -> String {
        let rubs = min(4, max(0, completedRubs))
        if rubs == 0 || rubs == 4 {
            return "Juz \(juz)"
        }
        let frac: String
        switch rubs {
        case 1: frac = "¼"
        case 2: frac = "½"
        case 3: frac = "¾"
        default: frac = ""
        }
        return "Juz \(juz)\(frac)"
    }

    static func averageUnits(finishNight: Int) -> Double {
        let n = TaraweehPlan.clampedFinishNight(finishNight)
        return Double(totalRubUnits) / Double(n)
    }

    static func averageLoadLabel(finishNight: Int) -> String {
        let avgUnits = averageUnits(finishNight: finishNight)
        let nearest = max(1, Int(avgUnits.rounded()))
        return "~\(juzLabel(units: nearest)) juz / night"
    }

    static func juzLabel(units: Int) -> String {
        let whole = units / 4
        let frac = units % 4
        let fracPart: String
        switch frac {
        case 1: fracPart = "¼"
        case 2: fracPart = "½"
        case 3: fracPart = "¾"
        default: fracPart = ""
        }
        if whole == 0 {
            return fracPart.isEmpty ? "0" : fracPart
        }
        if fracPart.isEmpty {
            return "\(whole)"
        }
        return "\(whole)\(fracPart)"
    }

    /// Juz segments for a mushaf: prefer ReciteViewModel's loaded list, else bundled fallback.
    static func juzSegments(mushafID: Int, loaded: [NavigationSegment]) -> [NavigationSegment] {
        if !loaded.isEmpty { return loaded }
        let entries = SegmentsLoader.loadBundledSegments()
        return SegmentsLoader.bundledFallback(mushafID: mushafID, entries: entries).juz
    }
}
