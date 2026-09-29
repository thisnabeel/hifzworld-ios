import Foundation

struct JournalRecording: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    var title: String
    let fileName: String
    var pageNumbers: [Int]
    var mushafID: Int
    var startedPage: Int?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        title: String = "",
        fileName: String? = nil,
        pageNumbers: [Int] = [],
        mushafID: Int = 2,
        startedPage: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.title = title
        self.fileName = fileName ?? "\(id.uuidString).m4a"
        self.pageNumbers = pageNumbers.sorted()
        self.mushafID = mushafID
        self.startedPage = startedPage
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return DeckRecording.defaultTitle(for: createdAt)
    }

    var pagesLabel: String {
        let pages = pageNumbers.sorted()
        guard !pages.isEmpty else { return "No pages" }
        if pages.count == 1 { return "p. \(pages[0])" }
        let collapsed = Self.collapsedRanges(pages)
        return collapsed
    }

    private static func collapsedRanges(_ pages: [Int]) -> String {
        var parts: [String] = []
        var start = pages[0]
        var prev = pages[0]
        for page in pages.dropFirst() {
            if page == prev + 1 {
                prev = page
                continue
            }
            parts.append(start == prev ? "\(start)" : "\(start)–\(prev)")
            start = page
            prev = page
        }
        parts.append(start == prev ? "\(start)" : "\(start)–\(prev)")
        return "p. " + parts.joined(separator: ", ")
    }

    var surahNames: [String] {
        var seen = Set<Int>()
        var names: [String] = []
        var pages: [Int] = []
        if let startedPage {
            pages.append(startedPage)
        }
        pages.append(contentsOf: pageNumbers)
        for page in pages {
            guard let number = BundlePageGrouping.resolvedSurahNumber(for: page, overrides: [:]),
                  seen.insert(number).inserted
            else { continue }
            names.append(BundlePageGrouping.englishName(forSurahNumber: number))
        }
        return names
    }

    var timestampLabel: String {
        DeckRecording.defaultTitle(for: createdAt)
    }

    var surahNamesLabel: String {
        surahNames.joined(separator: ", ")
    }
}
