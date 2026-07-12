import Foundation

struct Reciter: Codable, Identifiable, Hashable {
    let id: Int
    let slug: String
    let name: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name
        case avatarURL = "avatar_url"
    }
}

struct Recitation: Codable, Identifiable, Hashable {
    var id: Int { recitationID }
    let recitationID: Int
    let surahPosition: Int?
    let surahName: String?
    let riwayahSlug: String?
    let riwayahTitle: String?
    let audioURL: String?

    enum CodingKeys: String, CodingKey {
        case recitationID = "recitation_id"
        case surahPosition = "surah_position"
        case surahName = "surah_name"
        case riwayahSlug = "riwayah_slug"
        case riwayahTitle = "riwayah_title"
        case audioURL = "audio_url"
    }
}

struct VerseSegment: Codable, Identifiable, Hashable {
    var id: String { verse }
    let verse: String
    let startTime: Double?
    let endTime: Double?

    enum CodingKeys: String, CodingKey {
        case verse
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct VerseSegmentLookup: Codable {
    let audioURL: String?
    let recitationID: Int?
    let verse: String?
    let startTime: Double?
    let endTime: Double?
    let surahPosition: Int?
    let reciterSlug: String?
    let riwayahSlug: String?
    let riwayahTitle: String?

    enum CodingKeys: String, CodingKey {
        case verse
        case audioURL = "audio_url"
        case recitationID = "recitation_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case surahPosition = "surah_position"
        case reciterSlug = "reciter_slug"
        case riwayahSlug = "riwayah_slug"
        case riwayahTitle = "riwayah_title"
    }
}
