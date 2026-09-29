import Foundation

@MainActor
struct MessagesService {
    private let api = HifzworldAPIClient.shared

    func list(withUserID: UUID? = nil) async throws -> [MessageDTO] {
        var query: [URLQueryItem] = []
        if let withUserID {
            query.append(URLQueryItem(name: "with", value: withUserID.uuidString.lowercased()))
        }
        let response: MessagesListResponse = try await api.get("/api/messages", query: query)
        return response.messages
    }

    func create(
        recipientID: UUID,
        body: String,
        pageNumbers: [Int],
        mushafID: Int
    ) async throws -> MessageDTO {
        let payload = CreateMessageBody(
            recipientID: recipientID,
            body: body,
            pageNumbers: pageNumbers,
            mushafID: mushafID
        )
        return try await api.post("/api/messages", body: payload)
    }

    func show(id: UUID) async throws -> MessageDTO {
        try await api.get("/api/messages/\(id.uuidString.lowercased())")
    }

    func markRead(id: UUID) async throws -> MessageDTO {
        try await api.post("/api/messages/\(id.uuidString.lowercased())/read")
    }

    func unreadCount() async throws -> Int {
        let response: MessagesUnreadCountResponse = try await api.get("/api/messages/unread_count")
        return response.count
    }
}
