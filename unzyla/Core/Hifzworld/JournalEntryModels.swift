import Foundation

struct JournalEntryDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let entryDate: String
    let body: String
    let timeZone: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body
        case userID = "user_id"
        case entryDate = "entry_date"
        case timeZone = "time_zone"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var calendarDate: Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: entryDate)
    }
}

struct JournalEntriesResponse: Codable {
    let journalEntries: [JournalEntryDTO]
    let today: String?

    enum CodingKeys: String, CodingKey {
        case journalEntries = "journal_entries"
        case today
    }
}
