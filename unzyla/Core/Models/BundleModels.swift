import Foundation

struct MushafBundle: Identifiable, Codable, Hashable {
    let id: UUID
    var serverID: UUID?
    var title: String
    var description: String
    var pageNumbers: [Int]
    var mushafID: Int
    var isShared: Bool
    var collaboratorUserID: UUID?
    var collaboratorName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverID: UUID? = nil,
        title: String,
        description: String,
        pageNumbers: [Int] = [],
        mushafID: Int = 3,
        isShared: Bool = false,
        collaboratorUserID: UUID? = nil,
        collaboratorName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.description = description
        self.pageNumbers = pageNumbers
        self.mushafID = mushafID
        self.isShared = isShared
        self.collaboratorUserID = collaboratorUserID
        self.collaboratorName = collaboratorName
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
        mushafID = try container.decodeIfPresent(Int.self, forKey: .mushafID) ?? 3
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        collaboratorUserID = try container.decodeIfPresent(UUID.self, forKey: .collaboratorUserID)
        collaboratorName = try container.decodeIfPresent(String.self, forKey: .collaboratorName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, pageNumbers, mushafID, isShared, createdAt, updatedAt
        case serverID = "server_id"
        case collaboratorUserID = "collaborator_user_id"
        case collaboratorName = "collaborator_name"
    }
}
