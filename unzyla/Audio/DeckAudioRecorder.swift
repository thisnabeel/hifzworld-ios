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

        // Switching decks discards an in-progress take.
        _ = stopRecording(save: false)

        let recordingID = UUID()
        let url = DeckRecordingStore.shared.newRecordingURL(deckID: deckID, recordingID: recordingID)
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
            activeDeckID = deckID
            activeDeckTitle = deckTitle
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
        stopRecording(save: true)
    }

    func cancel() {
        _ = stopRecording(save: false)
    }

    @discardableResult
    private func stopRecording(save: Bool) -> DeckRecording? {
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

        defer {
            startedAt = nil
            activeURL = nil
            activeRecordingID = nil
            activeDeckID = nil
            activeDeckTitle = nil
            elapsed = 0
        }

        guard save,
              let url,
              let recordingID,
              let deckID
        else {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        }

        // Ignore accidental taps that produce tiny empty files.
        guard duration >= 0.4, FileManager.default.fileExists(atPath: url.path) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let recording = DeckRecording(
            id: recordingID,
            deckID: deckID,
            createdAt: createdAt,
            duration: duration,
            title: DeckRecording.defaultTitle(for: createdAt),
            fileName: url.lastPathComponent
        )
        DeckRecordingStore.shared.save(recording)
        return recording
    }

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
