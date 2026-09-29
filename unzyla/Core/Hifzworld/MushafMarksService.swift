import Foundation

@MainActor
struct MushafMarksService {
    private let api = HifzworldAPIClient.shared

    func list(
        subjectID: UUID? = nil,
        markerID: UUID? = nil,
        page: Int? = nil,
        mushafID: Int? = nil,
        from: Date? = nil,
        to: Date? = nil,
        limit: Int = 200
    ) async throws -> [MushafMarkDTO] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let subjectID {
            query.append(URLQueryItem(name: "subject_id", value: subjectID.uuidString.lowercased()))
        }
        if let markerID {
            query.append(URLQueryItem(name: "marker_id", value: markerID.uuidString.lowercased()))
        }
        if let page {
            query.append(URLQueryItem(name: "page", value: String(page)))
        }
        if let mushafID {
            query.append(URLQueryItem(name: "mushaf_id", value: String(mushafID)))
        }
        if let from {
            query.append(URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from)))
        }
        if let to {
            query.append(URLQueryItem(name: "to", value: ISO8601DateFormatter().string(from: to)))
        }

        let response: MushafMarksResponse = try await api.get("/api/mushaf_marks", query: query)
        return response.marks
    }

    func create(
        subjectID: UUID,
        wordID: Int,
        verseKey: String,
        pageNumber: Int,
        mushafID: Int,
        markType: MistakeMarkType,
        note: String? = nil,
        lineNumber: Int? = nil,
        wordPosition: Int? = nil,
        markedAt: Date = Date()
    ) async throws -> MushafMarkDTO {
        let body = CreateMushafMarkBody(
            subjectID: subjectID,
            wordID: wordID,
            verseKey: verseKey,
            pageNumber: pageNumber,
            mushafID: mushafID,
            markType: markType.rawValue,
            note: note,
            lineNumber: lineNumber,
            wordPosition: wordPosition,
            markedAt: markedAt
        )
        return try await api.post("/api/mushaf_marks", body: body)
    }

    func unmark(id: UUID, at date: Date = Date()) async throws {
        do {
            let _: MushafMarkDTO = try await api.patch(
                "/api/mushaf_marks/\(id.uuidString.lowercased())",
                body: UnmarkMushafMarkBody(unmarkedAt: date)
            )
        } catch {
            if case APIError.httpStatus(let code, _) = error, code == 404 || code == 405 || code == 422 {
                try await api.delete("/api/mushaf_marks/\(id.uuidString.lowercased())")
                return
            }
            throw error
        }
    }

    func createHeat(markID: UUID) async throws -> MushafHeatDTO {
        try await api.post("/api/mushaf_marks/\(markID.uuidString.lowercased())/heats")
    }
}

private struct UnmarkMushafMarkBody: Encodable {
    let unmarkedAt: Date

    enum CodingKeys: String, CodingKey {
        case unmarkedAt = "unmarked_at"
    }
}

private struct CreateMushafMarkBody: Encodable {
    let subjectID: UUID
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
        case subjectID = "subject_id"
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
        try container.encode(subjectID, forKey: .subjectID)
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
