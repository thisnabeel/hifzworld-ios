import Foundation

@MainActor
struct FriendsService {
    private let api = HifzworldAPIClient.shared

    func list() async throws -> FriendshipsResponse {
        try await api.get("/api/friendships")
    }

    func add(email: String?, handle: String?) async throws -> FriendshipDTO {
        let body = AddFriendBody(email: email, handle: handle)
        return try await api.post("/api/friendships", body: body)
    }

    func accept(id: UUID) async throws -> FriendshipDTO {
        try await api.post("/api/friendships/\(id.uuidString.lowercased())/accept")
    }

    func remove(id: UUID) async throws {
        try await api.delete("/api/friendships/\(id.uuidString.lowercased())")
    }

    func bundles(forFriendUserID userID: UUID) async throws -> FriendBundlesResponse {
        try await api.get("/api/friends/\(userID.uuidString.lowercased())/bundles")
    }

    func createBundle(
        forFriendUserID userID: UUID,
        title: String,
        description: String,
        mushafID: Int,
        pageNumbers: [Int] = []
    ) async throws -> RemoteMushafBundle {
        let body = CreateFriendBundleBody(
            title: title,
            description: description,
            pageNumbers: pageNumbers,
            mushafID: mushafID
        )
        return try await api.post(
            "/api/friends/\(userID.uuidString.lowercased())/bundles",
            body: body
        )
    }
}

private struct AddFriendBody: Encodable {
    let email: String?
    let handle: String?
}

private struct CreateFriendBundleBody: Encodable {
    let title: String
    let description: String
    let pageNumbers: [Int]
    let mushafID: Int

    enum CodingKeys: String, CodingKey {
        case title, description
        case pageNumbers = "page_numbers"
        case mushafID = "mushaf_id"
    }
}
