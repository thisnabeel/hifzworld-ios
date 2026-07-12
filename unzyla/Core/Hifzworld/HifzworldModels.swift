import Foundation

struct HifzworldUser: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String?
    let handle: String?
    let displayName: String
    let avatarURL: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AuthResponse: Codable {
    let token: String
    let user: HifzworldUser
}

struct RemoteMushafBundle: Codable, Identifiable, Hashable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let description: String
    let pageNumbers: [Int]
    let mushafID: Int
    let role: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, role
        case ownerID = "owner_id"
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BundleMineResponse: Codable {
    let owned: [RemoteMushafBundle]
    let shared: [RemoteMushafBundle]
}

struct BundleShareDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let mushafBundleID: UUID
    let sharedByID: UUID
    let sharedWithID: UUID
    let status: String
    let bundle: RemoteMushafBundle?
    let sharedBy: HifzworldUser?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, bundle
        case mushafBundleID = "mushaf_bundle_id"
        case sharedByID = "shared_by_id"
        case sharedWithID = "shared_with_id"
        case sharedBy = "shared_by"
        case createdAt = "created_at"
    }
}

struct ReviewSessionDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let mushafBundleID: UUID
    let bundleTitle: String
    let reciterID: UUID
    let listenerID: UUID
    let reciter: HifzworldUser?
    let listener: HifzworldUser?
    let status: String
    let videoRoomID: String?
    let startedAt: Date?
    let endedAt: Date?
    let livekit: LiveKitCredentials?
    let markCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, status, reciter, listener, livekit
        case mushafBundleID = "mushaf_bundle_id"
        case bundleTitle = "bundle_title"
        case reciterID = "reciter_id"
        case listenerID = "listener_id"
        case videoRoomID = "video_room_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case markCount = "mark_count"
    }
}

struct LiveKitCredentials: Codable, Hashable {
    let url: String?
    let token: String?
    let room: String?
    let note: String?
}

struct SessionMarkDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let reviewSessionID: UUID
    let mushafBundleID: UUID
    let listenerID: UUID
    let listenerDisplayName: String?
    let wordID: Int
    let verseKey: String
    let pageNumber: Int
    let mushafID: Int
    let markType: String
    let note: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, note
        case reviewSessionID = "review_session_id"
        case mushafBundleID = "mushaf_bundle_id"
        case listenerID = "listener_id"
        case listenerDisplayName = "listener_display_name"
        case wordID = "word_id"
        case verseKey = "verse_key"
        case pageNumber = "page_number"
        case mushafID = "mushaf_id"
        case markType = "mark_type"
        case createdAt = "created_at"
    }
}

struct FeedbackSessionDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let mushafBundleID: UUID
    let bundleTitle: String
    let reciterID: UUID
    let listenerID: UUID
    let reciter: HifzworldUser?
    let listener: HifzworldUser?
    let status: String
    let startedAt: Date?
    let endedAt: Date?
    let markCount: Int?
    let marks: [SessionMarkDTO]

    enum CodingKeys: String, CodingKey {
        case id, status, reciter, listener, marks
        case mushafBundleID = "mushaf_bundle_id"
        case bundleTitle = "bundle_title"
        case reciterID = "reciter_id"
        case listenerID = "listener_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case markCount = "mark_count"
    }
}

enum MistakeMarkType: String, CaseIterable, Identifiable {
    case tajweed
    case pronunciation
    case skipped
    case added
    case hesitation
    case other

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct ReviewSessionContext: Equatable {
    enum Role: Equatable {
        case reciter
        case listener
    }

    let sessionID: UUID
    let bundleServerID: UUID
    let role: Role
    let partnerName: String
    let livekitURL: String?
    let livekitToken: String?
}

struct APIErrorResponse: Codable {
    let error: String
}
