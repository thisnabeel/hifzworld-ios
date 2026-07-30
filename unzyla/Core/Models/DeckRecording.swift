import Foundation

struct DeckRecording: Identifiable, Codable, Hashable {
    let id: UUID
    let deckID: UUID
    let createdAt: Date
    var duration: TimeInterval
    var title: String
    let fileName: String
    /// Mushaf word id → paint style applied during this take.
    var marks: [String: WordPaintStyle]

    init(
        id: UUID = UUID(),
        deckID: UUID,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        title: String = "",
        fileName: String? = nil,
        marks: [String: WordPaintStyle] = [:]
    ) {
        self.id = id
        self.deckID = deckID
        self.createdAt = createdAt
        self.duration = duration
        self.title = title
        self.fileName = fileName ?? "\(id.uuidString).m4a"
        self.marks = marks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        deckID = try container.decode(UUID.self, forKey: .deckID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        fileName = try container.decode(String.self, forKey: .fileName)
        marks = try container.decodeIfPresent([String: WordPaintStyle].self, forKey: .marks) ?? [:]
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.defaultTitle(for: createdAt)
    }

    var markCount: Int { marks.count }

    var paintedWords: [Int: WordPaintStyle] {
        var map: [Int: WordPaintStyle] = [:]
        for (key, style) in marks {
            if let id = Int(key) {
                map[id] = style
            }
        }
        return map
    }

    static func encodeMarks(_ painted: [Int: WordPaintStyle]) -> [String: WordPaintStyle] {
        Dictionary(uniqueKeysWithValues: painted.map { (String($0.key), $0.value) })
    }

    static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private enum CodingKeys: String, CodingKey {
        case id, deckID, createdAt, duration, title, fileName, marks
    }
}
