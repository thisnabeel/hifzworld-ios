import Foundation

struct MessageDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let sender: HifzworldUser?
    let recipient: HifzworldUser?
    let body: String
    let pageNumbers: [Int]
    let mushafID: Int
    let readAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body, sender, recipient
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
        case readAt = "read_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isUnread: Bool { readAt == nil }

    var senderLabel: String {
        if let handle = sender?.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return sender?.displayName ?? "Friend"
    }
}

struct MessagesListResponse: Decodable {
    let messages: [MessageDTO]
}

struct MessagesUnreadCountResponse: Decodable {
    let count: Int
}

struct CreateMessageBody: Encodable {
    let recipientID: UUID
    let body: String
    let pageNumbers: [Int]
    let mushafID: Int

    enum CodingKeys: String, CodingKey {
        case body
        case recipientID = "recipient_id"
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
    }
}
