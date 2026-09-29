import Foundation

@MainActor
struct ReviewSessionService {
    private let api = HifzworldAPIClient.shared

    func start(bundleServerID: UUID, listenerID: UUID) async throws -> ReviewSessionDTO {
        let body = StartSessionBody(mushafBundleID: bundleServerID, listenerID: listenerID)
        return try await api.post("/api/review_sessions", body: body)
    }

    func join(sessionID: UUID) async throws -> ReviewSessionDTO {
        try await api.post("/api/review_sessions/\(sessionID.uuidString.lowercased())/join")
    }

    func end(sessionID: UUID) async throws -> ReviewSessionDTO {
        try await api.patch("/api/review_sessions/\(sessionID.uuidString.lowercased())/end")
    }

    func fetchSession(sessionID: UUID) async throws -> ReviewSessionDTO {
        try await api.get("/api/review_sessions/\(sessionID.uuidString.lowercased())")
    }

    func updateState(sessionID: UUID, currentPage: Int?, pageHidden: Bool?) async throws -> ReviewSessionDTO {
        let body = UpdateStateBody(currentPage: currentPage, pageHidden: pageHidden)
        return try await api.patch(
            "/api/review_sessions/\(sessionID.uuidString.lowercased())/state",
            body: body
        )
    }

    func pendingSession(bundleServerID: UUID) async throws -> ReviewSessionDTO {
        try await api.get(
            "/api/review_sessions/pending",
            query: [URLQueryItem(name: "mushaf_bundle_id", value: bundleServerID.uuidString.lowercased())]
        )
    }

    func fetchMarks(sessionID: UUID) async throws -> [SessionMarkDTO] {
        try await api.get("/api/review_sessions/\(sessionID.uuidString.lowercased())/marks")
    }

    func createMark(
        sessionID: UUID,
        wordID: Int,
        verseKey: String,
        pageNumber: Int,
        mushafID: Int,
        markType: MistakeMarkType,
        note: String?,
        lineNumber: Int? = nil,
        wordPosition: Int? = nil
    ) async throws -> SessionMarkDTO {
        let body = CreateMarkBody(
            wordID: wordID,
            verseKey: verseKey,
            pageNumber: pageNumber,
            mushafID: mushafID,
            markType: markType.rawValue,
            note: note,
            lineNumber: lineNumber,
            wordPosition: wordPosition,
            markedAt: Date()
        )
        return try await api.post(
            "/api/review_sessions/\(sessionID.uuidString.lowercased())/marks",
            body: body
        )
    }

    func unmarkMark(id: UUID, at date: Date = Date()) async throws {
        do {
            let _: SessionMarkDTO = try await api.patch(
                "/api/session_marks/\(id.uuidString.lowercased())",
                body: UnmarkSessionMarkBody(unmarkedAt: date)
            )
        } catch {
            if case APIError.httpStatus(let code, _) = error, code == 404 || code == 405 || code == 422 {
                try await api.delete("/api/session_marks/\(id.uuidString.lowercased())")
                return
            }
            throw error
        }
    }

    func fetchFeedback() async throws -> [FeedbackSessionDTO] {
        try await api.get("/api/users/me/feedback")
    }
}

private struct StartSessionBody: Encodable {
    let mushafBundleID: UUID
    let listenerID: UUID

    enum CodingKeys: String, CodingKey {
        case mushafBundleID = "mushaf_bundle_id"
        case listenerID = "listener_id"
    }
}

private struct UpdateStateBody: Encodable {
    let currentPage: Int?
    let pageHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case pageHidden = "page_hidden"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let currentPage {
            try container.encode(currentPage, forKey: .currentPage)
        }
        if let pageHidden {
            try container.encode(pageHidden, forKey: .pageHidden)
        }
    }
}

private struct CreateMarkBody: Encodable {
    let wordID: Int
    let verseKey: String
    let pageNumber: Int
    let mushafID: Int
    let markType: String
    let note: String?
    let lineNumber: Int?
    let wordPosition: Int?
    let markedAt: Date?

    enum CodingKeys: String, CodingKey {
        case note
        case wordID = "word_id"
        case verseKey = "verse_key"
        case pageNumber = "page_number"
        case mushafID = "mushaf_id"
        case markType = "mark_type"
        case lineNumber = "line_number"
        case wordPosition = "word_position"
        case markedAt = "marked_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wordID, forKey: .wordID)
        try container.encode(verseKey, forKey: .verseKey)
        try container.encode(pageNumber, forKey: .pageNumber)
        try container.encode(mushafID, forKey: .mushafID)
        try container.encode(markType, forKey: .markType)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(lineNumber, forKey: .lineNumber)
        try container.encodeIfPresent(wordPosition, forKey: .wordPosition)
        try container.encodeIfPresent(markedAt, forKey: .markedAt)
    }
}

private struct UnmarkSessionMarkBody: Encodable {
    let unmarkedAt: Date

    enum CodingKeys: String, CodingKey {
        case unmarkedAt = "unmarked_at"
    }
}
