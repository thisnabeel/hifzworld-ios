import Foundation

struct MushafBundle: Identifiable, Codable, Hashable {
    let id: UUID
    var serverID: UUID?
    var title: String
    var description: String
    var pageNumbers: [Int]
    /// Page number → surah number for list grouping (boundary pages that span two surahs).
    var pageSurahOverrides: [Int: Int]
    var mushafID: Int
    var isShared: Bool
    var collaboratorUserID: UUID?
    var collaboratorName: String?
    var shareStatus: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverID: UUID? = nil,
        title: String,
        description: String,
        pageNumbers: [Int] = [],
        pageSurahOverrides: [Int: Int] = [:],
        mushafID: Int = 3,
        isShared: Bool = false,
        collaboratorUserID: UUID? = nil,
        collaboratorName: String? = nil,
        shareStatus: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.description = description
        self.pageNumbers = pageNumbers
        self.pageSurahOverrides = pageSurahOverrides
        self.mushafID = mushafID
        self.isShared = isShared
        self.collaboratorUserID = collaboratorUserID
        self.collaboratorName = collaboratorName
        self.shareStatus = shareStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        serverID = try container.decodeIfPresent(UUID.self, forKey: .serverID)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        pageNumbers = try container.decodeIfPresent([Int].self, forKey: .pageNumbers) ?? []
        if let intKeyed = try container.decodeIfPresent([Int: Int].self, forKey: .pageSurahOverrides) {
            pageSurahOverrides = intKeyed
        } else if let stringKeyed = try container.decodeIfPresent([String: Int].self, forKey: .pageSurahOverrides) {
            pageSurahOverrides = Dictionary(
                uniqueKeysWithValues: stringKeyed.compactMap { key, value in
                    Int(key).map { ($0, value) }
                }
            )
        } else {
            pageSurahOverrides = [:]
        }
        mushafID = try container.decodeIfPresent(Int.self, forKey: .mushafID) ?? 3
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        collaboratorUserID = try container.decodeIfPresent(UUID.self, forKey: .collaboratorUserID)
        collaboratorName = try container.decodeIfPresent(String.self, forKey: .collaboratorName)
        shareStatus = try container.decodeIfPresent(String.self, forKey: .shareStatus)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(serverID, forKey: .serverID)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(pageNumbers, forKey: .pageNumbers)
        let stringKeyed = Dictionary(uniqueKeysWithValues: pageSurahOverrides.map { (String($0.key), $0.value) })
        try container.encode(stringKeyed, forKey: .pageSurahOverrides)
        try container.encode(mushafID, forKey: .mushafID)
        try container.encode(isShared, forKey: .isShared)
        try container.encodeIfPresent(collaboratorUserID, forKey: .collaboratorUserID)
        try container.encodeIfPresent(collaboratorName, forKey: .collaboratorName)
        try container.encodeIfPresent(shareStatus, forKey: .shareStatus)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, pageNumbers, mushafID, isShared, createdAt, updatedAt
        case pageSurahOverrides
        case serverID = "server_id"
        case collaboratorUserID = "collaborator_user_id"
        case collaboratorName = "collaborator_name"
        case shareStatus = "share_status"
    }
}
