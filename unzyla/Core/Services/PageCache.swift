import Foundation

nonisolated struct CachedMushafPageEnvelope: Codable, Sendable {
    let fetchedAt: Date
    let page: MushafPage
}

actor PageCache {
    private var pages: [Int: MushafPage] = [:]
    private var fetchedAtByPage: [Int: Date] = [:]
    private var mushafID: Int?

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func setMushaf(_ id: Int) {
        if mushafID != id {
            pages.removeAll()
            fetchedAtByPage.removeAll()
            mushafID = id
        }
    }

    func page(_ position: Int) -> MushafPage? {
        if let cached = pages[position] {
            return cached
        }
        guard let envelope = readEnvelope(position) else { return nil }
        pages[position] = envelope.page
        fetchedAtByPage[position] = envelope.fetchedAt
        return envelope.page
    }

    func fetchedAt(_ position: Int) -> Date? {
        if let date = fetchedAtByPage[position] {
            return date
        }
        return readEnvelope(position)?.fetchedAt
    }

    func hasDiskPage(_ position: Int) -> Bool {
        if pages[position] != nil { return true }
        guard let url = pageURL(position) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func missingPositions(in range: ClosedRange<Int>) -> [Int] {
        range.filter { !hasDiskPage($0) }
    }

    /// Persist a network fetch. `intoMemory` false keeps hydration from filling RAM with every page.
    func store(_ page: MushafPage, intoMemory: Bool = true, fetchedAt: Date = Date()) {
        if intoMemory {
            pages[page.position] = page
            fetchedAtByPage[page.position] = fetchedAt
        }
        writeEnvelope(CachedMushafPageEnvelope(fetchedAt: fetchedAt, page: page))
    }

    func removeAll() {
        pages.removeAll()
        fetchedAtByPage.removeAll()
    }

    // MARK: - Disk

    private func readEnvelope(_ position: Int) -> CachedMushafPageEnvelope? {
        guard let url = pageURL(position),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.isoFormatter.date(from: raw) {
                return date
            }
            return ISO8601DateFormatter().date(from: raw) ?? Date.distantPast
        }
        return try? decoder.decode(CachedMushafPageEnvelope.self, from: data)
    }

    private func writeEnvelope(_ envelope: CachedMushafPageEnvelope) {
        guard let url = pageURL(envelope.page.position) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(Self.isoFormatter.string(from: date))
            }
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            // Disk is best-effort; online reading must keep working.
        }
    }

    private func pageURL(_ position: Int) -> URL? {
        guard let mushafID else { return nil }
        return Self.directory(for: mushafID).appendingPathComponent("\(position).json")
    }

    private static func directory(for mushafID: Int) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("mushafs", isDirectory: true)
            .appendingPathComponent(String(mushafID), isDirectory: true)
            .appendingPathComponent("pages", isDirectory: true)
    }
}
