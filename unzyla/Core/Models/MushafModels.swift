import Foundation

struct GlobalConfigResponse: Codable {
    let minIosVersion: String?

    enum CodingKeys: String, CodingKey {
        case minIosVersion = "min_ios_version"
    }
}

struct MushafInfo: Codable {
    let id: Int
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case totalPages = "total_pages"
    }
}

struct MushafPage: Codable, Identifiable, Hashable {
    let id: Int
    let position: Int
    let lines: [MushafLine]
}

struct MushafLine: Codable, Identifiable, Hashable {
    let id: Int
    let position: Int
    let surahHeaderPosition: Int?
    let suppressLine: Bool?
    let words: [MushafWord]

    enum CodingKeys: String, CodingKey {
        case id, position, words
        case surahHeaderPosition = "surah_header_position"
        case suppressLine = "suppress_line"
    }
}

struct MushafWord: Codable, Identifiable, Hashable {
    let id: Int
    let position: Int
    let content: String
    let ayah: String?
    let layout: WordLayout?
}

struct WordLayout: Codable, Hashable {
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
}

struct MushafSegment: Codable, Identifiable {
    let id: Int
    let startPage: Int
    let endPage: Int
    let title: String
    let categoryPosition: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case startPage = "start_page"
        case endPage = "end_page"
        case categoryPosition = "category_position"
    }
}

struct SurahHeaderMarkersResponse: Codable {
    let byPage: [String: [Int]]?

    enum CodingKeys: String, CodingKey {
        case byPage = "by_page"
    }
}

struct WordDetail: Codable {
    let id: Int
    let content: String?
    let ayah: String?
}

struct SegmentJSONEntry: Codable {
    let fields: SegmentFields
}

struct SegmentFields: Codable {
    let firstPage: Int
    let lastPage: Int
    let title: String
    let category: String
    let categoryPosition: Int?

    enum CodingKeys: String, CodingKey {
        case title, category
        case firstPage = "first_page"
        case lastPage = "last_page"
        case categoryPosition = "category_position"
    }
}

enum MushafID: Int, CaseIterable, Identifiable {
    case indoPak = 2
    case uthmani = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .indoPak: return "13 Liner IndoPak"
        case .uthmani: return "15 Liner Uthmani"
        }
    }

    var subtitle: String {
        switch self {
        case .indoPak: return "South Asian style · 13 lines per page"
        case .uthmani: return "Madinah style · 15 lines per page"
        }
    }

    var maxLines: Int {
        switch self {
        case .indoPak: return 13
        case .uthmani: return 15
        }
    }
}