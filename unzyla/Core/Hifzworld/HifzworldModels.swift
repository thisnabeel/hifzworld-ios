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

    init(
        id: UUID,
        email: String?,
        handle: String?,
        displayName: String,
        avatarURL: String?,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.email = email
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        handle = try container.decodeIfPresent(String.self, forKey: .handle)
        let rawName = try container.decodeIfPresent(String.self, forKey: .displayName)
        displayName = (rawName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "User"
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
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
    let collaboratorUserID: UUID?
    let collaboratorName: String?
    let shareStatus: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, role
        case ownerID = "owner_id"
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
        case collaboratorUserID = "collaborator_user_id"
        case collaboratorName = "collaborator_name"
        case shareStatus = "share_status"
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
    let currentPage: Int?
    let pageHidden: Bool?
    let videoRoomID: String?
    let startedAt: Date?
    let endedAt: Date?
    let markCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, status, reciter, listener
        case mushafBundleID = "mushaf_bundle_id"
        case bundleTitle = "bundle_title"
        case reciterID = "reciter_id"
        case listenerID = "listener_id"
        case currentPage = "current_page"
        case pageHidden = "page_hidden"
        case videoRoomID = "video_room_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case markCount = "mark_count"
    }
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
    let lineNumber: Int?
    let wordPosition: Int?
    let mushafID: Int
    let markType: String
    let note: String?
    let createdAt: Date?
    let markedAt: Date?
    let unmarkedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, note
        case reviewSessionID = "review_session_id"
        case mushafBundleID = "mushaf_bundle_id"
        case listenerID = "listener_id"
        case listenerDisplayName = "listener_display_name"
        case wordID = "word_id"
        case verseKey = "verse_key"
        case pageNumber = "page_number"
        case lineNumber = "line_number"
        case wordPosition = "word_position"
        case mushafID = "mushaf_id"
        case markType = "mark_type"
        case createdAt = "created_at"
        case markedAt = "marked_at"
        case unmarkedAt = "unmarked_at"
    }

    var isUnmarked: Bool { unmarkedAt != nil }
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

struct FriendshipDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let status: String
    let requesterID: UUID
    let recipientID: UUID
    let user: HifzworldUser?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, user
        case requesterID = "requester_id"
        case recipientID = "recipient_id"
        case createdAt = "created_at"
    }
}

struct FriendshipsResponse: Codable {
    let friends: [FriendshipDTO]
    let pendingIncoming: [FriendshipDTO]
    let pendingOutgoing: [FriendshipDTO]

    enum CodingKeys: String, CodingKey {
        case friends
        case pendingIncoming = "pending_incoming"
        case pendingOutgoing = "pending_outgoing"
    }
}

struct FriendBundlesResponse: Codable {
    let friend: HifzworldUser
    let bundles: [RemoteMushafBundle]
}

enum MistakeMarkType: String, CaseIterable, Identifiable {
    case mistake
    case tajweed

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    /// Maps legacy server values onto the two supported types.
    static func resolved(from raw: String?) -> MistakeMarkType {
        guard let raw, let type = MistakeMarkType(rawValue: raw) else {
            return .mistake
        }
        return type
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
    /// Reciter whose Mushaf is being marked during the live session.
    let reciterID: UUID
}

struct APIErrorResponse: Codable {
    let error: String
}

struct HifzworldAppConfig: Codable {
    let minAppVersion: String?
    let appStoreId: String?

    enum CodingKeys: String, CodingKey {
        case minAppVersion = "min_app_version"
        case appStoreId = "app_store_id"
    }
}
