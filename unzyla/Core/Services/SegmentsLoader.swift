import Foundation

enum SegmentsLoader {
    static func loadBundledSegments() -> [SegmentJSONEntry] {
        guard let url = Bundle.main.url(forResource: "segments", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SegmentJSONEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func juzSegments(from entries: [SegmentJSONEntry], mushafID: Int? = nil) -> [NavigationSegment] {
        entries
            .filter { $0.fields.category == "juz" }
            .filter { mushafID == nil || $0.fields.mushaf == nil || $0.fields.mushaf == mushafID }
            .map {
                NavigationSegment(
                    title: $0.fields.title,
                    startPage: $0.fields.firstPage,
                    endPage: $0.fields.lastPage,
                    categoryPosition: $0.fields.categoryPosition
                )
            }
            .sorted { $0.startPage > $1.startPage }
    }

    static func surahSegments(from entries: [SegmentJSONEntry], mushafID: Int? = nil) -> [NavigationSegment] {
        entries
            .filter { $0.fields.category == "surah" }
            .filter { mushafID == nil || $0.fields.mushaf == nil || $0.fields.mushaf == mushafID }
            .map {
                NavigationSegment(
                    title: $0.fields.title,
                    startPage: $0.fields.firstPage,
                    endPage: $0.fields.lastPage,
                    categoryPosition: $0.fields.categoryPosition
                )
            }
            .sorted { $0.startPage > $1.startPage }
    }

    static func fromAPI(_ segments: [MushafSegment]) -> [NavigationSegment] {
        segments
            .map {
                NavigationSegment(
                    title: $0.title,
                    startPage: $0.startPage,
                    endPage: $0.endPage,
                    categoryPosition: $0.categoryPosition
                )
            }
            .sorted { $0.startPage > $1.startPage }
    }

    /// 15-line Madinah (mushaf id 3) — used when the API has no segments for Uthmani.
    static func uthmaniJuzSegments() -> [NavigationSegment] {
        let ranges: [(Int, Int, Int)] = [
            (1, 1, 20), (2, 21, 39), (3, 40, 59), (4, 60, 79), (5, 80, 99),
            (6, 100, 119), (7, 120, 139), (8, 140, 159), (9, 160, 177), (10, 178, 201),
            (11, 202, 221), (12, 222, 241), (13, 242, 261), (14, 262, 281), (15, 282, 301),
            (16, 302, 321), (17, 322, 341), (18, 342, 361), (19, 362, 381), (20, 382, 401),
            (21, 402, 421), (22, 422, 441), (23, 442, 461), (24, 462, 481), (25, 482, 501),
            (26, 502, 521), (27, 522, 541), (28, 542, 561), (29, 562, 581), (30, 582, 604),
        ]
        return ranges.map {
            NavigationSegment(
                title: "Juz \($0.0)",
                startPage: $0.1,
                endPage: $0.2,
                categoryPosition: $0.0
            )
        }
        .sorted { $0.startPage > $1.startPage }
    }

    static func uthmaniSurahSegments() -> [NavigationSegment] {
        // Standard 15-line Madinah mushaf surah header pages.
        let starts: [Int] = [
            1, 2, 50, 77, 106, 128, 151, 177, 187, 208,
            221, 235, 249, 255, 262, 267, 282, 293, 305, 312,
            322, 332, 342, 350, 359, 367, 377, 385, 396, 404,
            411, 415, 418, 428, 434, 440, 446, 453, 458, 467,
            477, 483, 489, 496, 499, 502, 507, 511, 515, 518,
            520, 523, 526, 528, 531, 534, 537, 542, 545, 549,
            551, 553, 554, 556, 558, 560, 562, 564, 566, 568,
            570, 572, 574, 575, 577, 578, 580, 582, 583, 585,
            586, 587, 587, 589, 590, 591, 591, 592, 593, 594,
            595, 595, 596, 596, 597, 597, 598, 598, 599, 599,
            600, 600, 601, 601, 601, 602, 602, 602, 603, 603,
            603, 604, 604, 604,
        ]
        return starts.enumerated().map { index, start in
            let number = index + 1
            let end = index + 1 < starts.count ? max(start, starts[index + 1]) : 604
            return NavigationSegment(
                title: SurahMeta.arabicName(number),
                startPage: start,
                endPage: end,
                categoryPosition: number
            )
        }
        .sorted { $0.startPage > $1.startPage }
    }

    static func bundledFallback(mushafID: Int, entries: [SegmentJSONEntry]) -> (juz: [NavigationSegment], surah: [NavigationSegment]) {
        let juz = juzSegments(from: entries, mushafID: mushafID)
        let surah = surahSegments(from: entries, mushafID: mushafID)
        if mushafID == MushafID.uthmani.rawValue {
            return (
                juz.isEmpty ? uthmaniJuzSegments() : juz,
                surah.isEmpty ? uthmaniSurahSegments() : surah
            )
        }
        return (
            juz.isEmpty ? juzSegments(from: entries) : juz,
            surah.isEmpty ? surahSegments(from: entries) : surah
        )
    }
}

struct NavigationSegment: Identifiable, Hashable {
    var id: String { "\(startPage)-\(title)-\(categoryPosition ?? 0)" }
    let title: String
    let startPage: Int
    let endPage: Int
    let categoryPosition: Int?
}
