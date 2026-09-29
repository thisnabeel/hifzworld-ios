import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DeckAudioRecorder {
    static let shared = DeckAudioRecorder()

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var permissionDenied = false
    private(set) var activeDeckID: UUID?
    private(set) var activeDeckTitle: String?
    private(set) var isJournalSession = false
    var lastError: String?

    private var recorder: AVAudioRecorder?
    private var tickTimer: Timer?
    private var startedAt: Date?
    private var activeURL: URL?
    private var activeRecordingID: UUID?

    private init() {}

    func requestPermissionIfNeeded() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionDenied = false
            return true
        case .denied:
            permissionDenied = true
            return false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            permissionDenied = !granted
            return granted
        @unknown default:
            permissionDenied = true
            return false
        }
    }

    func start(deckID: UUID, deckTitle: String) async -> Bool {
        lastError = nil
        guard await requestPermissionIfNeeded() else {
            lastError = "Microphone access is required to record."
            return false
        }

        _ = finishCapture(save: false)

        let recordingID = UUID()
        let url = DeckRecordingStore.shared.newRecordingURL(deckID: deckID, recordingID: recordingID)
        let started = beginRecording(url: url, recordingID: recordingID)
        guard started else { return false }
        activeDeckID = deckID
        activeDeckTitle = deckTitle
        isJournalSession = false
        return true
    }

    func startJournalSession() async -> Bool {
        lastError = nil
        guard await requestPermissionIfNeeded() else {
            lastError = "Microphone access is required to record."
            return false
        }

        _ = finishCapture(save: false)

        let recordingID = UUID()
        let url = JournalRecordingStore.shared.newRecordingURL(recordingID: recordingID)
        let started = beginRecording(url: url, recordingID: recordingID)
        guard started else { return false }
        isJournalSession = true
        return true
    }

    private func beginRecording(url: URL, recordingID: UUID) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
                lastError = "Could not start recording."
                return false
            }

            recorder = audioRecorder
            activeURL = url
            activeRecordingID = recordingID
            startedAt = Date()
            elapsed = 0
            isRecording = true
            startTicker()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func stop() -> DeckRecording? {
        let snapshot = finishCapture(save: !isJournalSession)
        guard !snapshot.wasJournal, snapshot.save, let meta = snapshot.meta else { return nil }
        guard let deckID = snapshot.deckID else {
            try? FileManager.default.removeItem(at: meta.url)
            return nil
        }
        let recording = DeckRecording(
            id: meta.id,
            deckID: deckID,
            createdAt: meta.createdAt,
            duration: meta.duration,
            title: DeckRecording.defaultTitle(for: meta.createdAt),
            fileName: meta.url.lastPathComponent
        )
        DeckRecordingStore.shared.save(recording)
        return recording
    }

    struct JournalTake {
        let id: UUID
        let createdAt: Date
        let duration: TimeInterval
        let fileName: String
    }

    func stopJournalSession() -> JournalTake? {
        let snapshot = finishCapture(save: isJournalSession)
        guard snapshot.wasJournal, snapshot.save, let meta = snapshot.meta else { return nil }
        return JournalTake(
            id: meta.id,
            createdAt: meta.createdAt,
            duration: meta.duration,
            fileName: meta.url.lastPathComponent
        )
    }

    func cancel() {
        _ = finishCapture(save: false)
    }

    private struct CaptureSnapshot {
        let save: Bool
        let wasJournal: Bool
        let deckID: UUID?
        let meta: (id: UUID, createdAt: Date, duration: TimeInterval, url: URL)?
    }

    private func finishCapture(save: Bool) -> CaptureSnapshot {
        tickTimer?.invalidate()
        tickTimer = nil

        let duration = max(elapsed, recorder?.currentTime ?? 0)
        recorder?.stop()
        recorder = nil
        isRecording = false

        let url = activeURL
        let recordingID = activeRecordingID
        let deckID = activeDeckID
        let createdAt = startedAt ?? Date()
        let wasJournal = isJournalSession

        defer {
            startedAt = nil
            activeURL = nil
            activeRecordingID = nil
            activeDeckID = nil
            activeDeckTitle = nil
            isJournalSession = false
            elapsed = 0
        }

        guard save, let url, let recordingID else {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            return CaptureSnapshot(save: false, wasJournal: wasJournal, deckID: deckID, meta: nil)
        }

        let minimumDuration: TimeInterval = wasJournal ? 5 : 0.4
        guard duration >= minimumDuration, FileManager.default.fileExists(atPath: url.path) else {
            try? FileManager.default.removeItem(at: url)
            return CaptureSnapshot(save: false, wasJournal: wasJournal, deckID: deckID, meta: nil)
        }

        return CaptureSnapshot(
            save: true,
            wasJournal: wasJournal,
            deckID: deckID,
            meta: (recordingID, createdAt, duration, url)
        )
    }

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTick()
            }
        }
    }

    private func handleTick() {
        guard isRecording else { return }
        if let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
        } else {
            elapsed = recorder?.currentTime ?? 0
        }
    }
}
