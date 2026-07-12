import Foundation

enum SegmentsLoader {
    static func loadBundledSegments() -> [SegmentJSONEntry] {
        guard let url = Bundle.main.url(forResource: "segments", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SegmentJSONEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func juzSegments(from entries: [SegmentJSONEntry]) -> [NavigationSegment] {
        entries
            .filter { $0.fields.category == "juz" }
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

    static func surahSegments(from entries: [SegmentJSONEntry]) -> [NavigationSegment] {
        entries
            .filter { $0.fields.category == "surah" }
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
}

struct NavigationSegment: Identifiable, Hashable {
    var id: String { "\(startPage)-\(title)" }
    let title: String
    let startPage: Int
    let endPage: Int
    let categoryPosition: Int?
}
