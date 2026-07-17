import Foundation

@MainActor
struct AppFeedbackService {
    private let api = HifzworldAPIClient.shared

    func submit(message: String, category: AppFeedbackCategory, email: String? = nil) async throws -> AppFeedbackDTO {
        let body = SubmitAppFeedbackBody(
            message: message,
            category: category.rawValue,
            email: email
        )
        return try await api.post("/api/feedback", body: body)
    }
}

struct AppFeedbackDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let message: String
    let email: String?
    let category: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, message, email, category
        case createdAt = "created_at"
    }
}

private struct SubmitAppFeedbackBody: Encodable {
    let message: String
    let category: String
    let email: String?
}
