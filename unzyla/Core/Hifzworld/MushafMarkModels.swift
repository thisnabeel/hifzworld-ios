import Foundation

struct MushafMarkDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let subjectID: UUID
    let markerID: UUID
    let subject: HifzworldUser?
    let marker: HifzworldUser?
    let wordID: Int
    let verseKey: String
    let pageNumber: Int
    let lineNumber: Int?
    let wordPosition: Int?
    let mushafID: Int
    let markType: String
    let note: String?
    let createdAt: Date?
    let updatedAt: Date?
    let markedAt: Date?
    let unmarkedAt: Date?
    let heatsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, subject, marker, note
        case subjectID = "subject_id"
        case markerID = "marker_id"
        case wordID = "word_id"
        case verseKey = "verse_key"
        case pageNumber = "page_number"
        case lineNumber = "line_number"
        case wordPosition = "word_position"
        case mushafID = "mushaf_id"
        case markType = "mark_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case markedAt = "marked_at"
        case unmarkedAt = "unmarked_at"
        case heatsCount = "heats_count"
    }

    var heatCount: Int { heatsCount ?? 0 }

    var isUnmarked: Bool { unmarkedAt != nil }

    /// When the current mark cycle started (`marked_at`, falling back to `created_at`).
    var markedAtOrCreated: Date? { markedAt ?? createdAt }

    /// Accidental tap: added and undone within a minute.
    var wasUnmarkedWithinAMinute: Bool {
        guard let unmarkedAt, let markedAtOrCreated else { return false }
        return unmarkedAt.timeIntervalSince(markedAtOrCreated) < 60
    }

    var displayReference: String {
        if MushafWordVerse.isProvisionalVerseKey(verseKey) {
            if let lineNumber, let wordPosition {
                return "p.\(pageNumber) · L\(lineNumber) · W\(wordPosition)"
            }
            return "p.\(pageNumber)"
        }
        return verseKey
    }

    /// Stored in `note` so live-review origin survives without a new API column.
    static let liveReviewNote = "live_review"

    var isFromLiveReview: Bool {
        note == Self.liveReviewNote || (note?.hasPrefix("live_review") == true)
    }
}

struct MushafMarksResponse: Codable {
    let marks: [MushafMarkDTO]
}

struct MushafHeatDTO: Codable {
    let id: UUID
    let mushafMarkID: UUID
    let recordedByID: UUID
    let createdAt: Date?
    let heatsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case mushafMarkID = "mushaf_mark_id"
        case recordedByID = "recorded_by_id"
        case createdAt = "created_at"
        case heatsCount = "heats_count"
    }
}
