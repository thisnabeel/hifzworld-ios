import Foundation
import Observation

@MainActor
@Observable
final class DeckRecordingStore {
    static let shared = DeckRecordingStore()

    private let fileManager = FileManager.default
    private var cache: [UUID: [DeckRecording]] = [:]

    private init() {}

    func recordings(for deckID: UUID) -> [DeckRecording] {
        if let cached = cache[deckID] {
            return cached
        }
        let loaded = loadIndex(for: deckID)
            .filter { fileExists(for: $0, deckID: deckID) }
            .sorted { $0.createdAt > $1.createdAt }
        cache[deckID] = loaded
        return loaded
    }

    func count(for deckID: UUID) -> Int {
        recordings(for: deckID).count
    }

    func fileURL(for recording: DeckRecording) -> URL {
        directory(for: recording.deckID).appendingPathComponent(recording.fileName)
    }

    func newRecordingURL(deckID: UUID, recordingID: UUID) -> URL {
        ensureDirectory(for: deckID)
        return directory(for: deckID).appendingPathComponent("\(recordingID.uuidString).m4a")
    }

    func save(_ recording: DeckRecording) {
        var items = recordings(for: recording.deckID)
        if let index = items.firstIndex(where: { $0.id == recording.id }) {
            items[index] = recording
        } else {
            items.insert(recording, at: 0)
        }
        items.sort { $0.createdAt > $1.createdAt }
        cache[recording.deckID] = items
        persistIndex(items, for: recording.deckID)
    }

    func delete(_ recording: DeckRecording) {
        let url = fileURL(for: recording)
        try? fileManager.removeItem(at: url)
        var items = recordings(for: recording.deckID)
        items.removeAll { $0.id == recording.id }
        cache[recording.deckID] = items
        persistIndex(items, for: recording.deckID)
    }

    func deleteAll(for deckID: UUID) {
        let dir = directory(for: deckID)
        try? fileManager.removeItem(at: dir)
        cache[deckID] = []
    }

    private func directory(for deckID: UUID) -> URL {
        documentsRoot()
            .appendingPathComponent("DeckRecordings", isDirectory: true)
            .appendingPathComponent(deckID.uuidString, isDirectory: true)
    }

    private func documentsRoot() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func ensureDirectory(for deckID: UUID) {
        let dir = directory(for: deckID)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func indexURL(for deckID: UUID) -> URL {
        directory(for: deckID).appendingPathComponent("index.json")
    }

    private func loadIndex(for deckID: UUID) -> [DeckRecording] {
        let url = indexURL(for: deckID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DeckRecording].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func persistIndex(_ items: [DeckRecording], for deckID: UUID) {
        ensureDirectory(for: deckID)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL(for: deckID), options: .atomic)
    }

    private func fileExists(for recording: DeckRecording, deckID: UUID) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: recording).path)
    }
}
