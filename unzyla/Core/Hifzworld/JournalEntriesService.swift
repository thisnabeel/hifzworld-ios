import Foundation

@MainActor
struct JournalEntriesService {
    private let api = HifzworldAPIClient.shared

    func list(from: Date? = nil, to: Date? = nil) async throws -> JournalEntriesResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "time_zone", value: TimeZone.current.identifier)
        ]
        let formatter = Self.dateFormatter
        if let from {
            query.append(URLQueryItem(name: "from", value: formatter.string(from: from)))
        }
        if let to {
            query.append(URLQueryItem(name: "to", value: formatter.string(from: to)))
        }
        return try await api.get("/api/journal_entries", query: query)
    }

    func upsertToday(body: String) async throws -> JournalEntryDTO {
        let payload = JournalEntryBody(body: body, timeZone: TimeZone.current.identifier)
        return try await api.post("/api/journal_entries", body: payload)
    }

    func update(id: UUID, body: String) async throws -> JournalEntryDTO {
        let payload = JournalEntryBody(body: body, timeZone: TimeZone.current.identifier)
        return try await api.patch("/api/journal_entries/\(id.uuidString.lowercased())", body: payload)
    }

    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private struct JournalEntryBody: Encodable {
    let body: String
    let timeZone: String

    enum CodingKeys: String, CodingKey {
        case body
        case timeZone = "time_zone"
    }
}
