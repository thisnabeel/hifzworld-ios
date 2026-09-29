import Foundation
import Observation

@MainActor
@Observable
final class JournalRecordingStore {
    static let shared = JournalRecordingStore()

    private(set) var recordings: [JournalRecording] = []

    private let fileManager = FileManager.default
    private var didLoad = false

    private init() {
        recordings = loadIndex().filter { fileExists(for: $0) }.sorted { $0.createdAt > $1.createdAt }
        didLoad = true
    }

    func recordings(on date: Date, calendar: Calendar = .current) -> [JournalRecording] {
        recordings.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
    }

    func fileURL(for recording: JournalRecording) -> URL {
        directory().appendingPathComponent(recording.fileName)
    }

    func newRecordingURL(recordingID: UUID) -> URL {
        ensureDirectory()
        return directory().appendingPathComponent("\(recordingID.uuidString).m4a")
    }

    func save(_ recording: JournalRecording) {
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
        } else {
            recordings.insert(recording, at: 0)
        }
        recordings.sort { $0.createdAt > $1.createdAt }
        persistIndex()
    }

    func delete(_ recording: JournalRecording) {
        try? fileManager.removeItem(at: fileURL(for: recording))
        recordings.removeAll { $0.id == recording.id }
        persistIndex()
    }

    private func directory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JournalRecordings", isDirectory: true)
    }

    private func ensureDirectory() {
        let dir = directory()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func indexURL() -> URL {
        directory().appendingPathComponent("index.json")
    }

    private func loadIndex() -> [JournalRecording] {
        guard let data = try? Data(contentsOf: indexURL()),
              let decoded = try? JSONDecoder().decode([JournalRecording].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistIndex() {
        ensureDirectory()
        guard let data = try? JSONEncoder().encode(recordings) else { return }
        try? data.write(to: indexURL(), options: .atomic)
    }

    private func fileExists(for recording: JournalRecording) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: recording).path)
    }
}
