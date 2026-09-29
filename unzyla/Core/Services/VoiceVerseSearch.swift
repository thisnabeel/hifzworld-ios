import AVFoundation
import Foundation
import Observation

/// Find a verse by reciting it, using Tilawa's on-device recognizer.
@MainActor
@Observable
final class VoiceVerseSearch {
    static let shared = VoiceVerseSearch()

    enum Phase: Equatable {
        case idle
        case needsDownload
        case downloading(Double)
        case preparing
        case listening
        case finishing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Where the engine first locked on while listening (before an ayah is confirmed).
    private(set) var candidate: TilawaVerseMatch?
    /// Ayahs heard, in recitation order.
    private(set) var matches: [TilawaVerseMatch] = []
    /// Closest whole-ayah matches from the final transcript, excluding `matches`.
    private(set) var alternatives: [TilawaVerseMatch] = []
    private(set) var level: Float = 0
    private(set) var hasFinished = false

    static let maxListenSeconds: TimeInterval = 30

    private let recognizer = TilawaRecognizer.shared
    private var listenTimeout: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?

    var downloadSizeText: String {
        ByteCountFormatter.string(fromByteCount: TilawaAssets.totalBytes, countStyle: .file)
    }

    var isListening: Bool { phase == .listening }

    var isBusy: Bool {
        switch phase {
        case .downloading, .preparing, .listening, .finishing: return true
        default: return false
        }
    }

    /// Whether the sheet should show the voice panel at all.
    var isActive: Bool {
        phase != .idle || hasFinished || candidate != nil || !matches.isEmpty
    }

    private init() {
        // `shared` lives for the app's lifetime, so the callbacks reach it directly.
        recognizer.onEvents = { events in
            Task { @MainActor in VoiceVerseSearch.shared.apply(events) }
        }
        recognizer.onLevel = { level in
            Task { @MainActor in VoiceVerseSearch.shared.level = level }
        }
        recognizer.onError = { error in
            let message = error.localizedDescription
            Task { @MainActor in VoiceVerseSearch.shared.fail(message) }
        }
    }

    /// The mic button: start, or stop and finalize.
    func toggle() {
        switch phase {
        case .listening:
            stop()
        case .idle, .failed:
            begin()
        case .needsDownload:
            dismissPanel()
        case .downloading, .preparing, .finishing:
            break
        }
    }

    func begin() {
        resetResults()
        guard TilawaAssets.isInstalled else {
            phase = .needsDownload
            return
        }
        prepareAndListen()
    }

    func download() {
        guard phase == .needsDownload || isFailed else { return }
        phase = .downloading(0)
        setupTask = Task { [weak self] in
            do {
                try await TilawaAssets.install { fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(fraction)
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.prepareAndListen()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard phase == .listening else { return }
        listenTimeout?.cancel()
        phase = .finishing
        level = 0
        recognizer.stop()
    }

    /// Stop everything and clear results (e.g. when the sheet closes).
    func cancel() {
        setupTask?.cancel()
        listenTimeout?.cancel()
        if phase == .listening || phase == .finishing { recognizer.cancel() }
        phase = .idle
        level = 0
        resetResults()
    }

    func dismissPanel() {
        cancel()
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func resetResults() {
        candidate = nil
        matches = []
        alternatives = []
        hasFinished = false
    }

    private func prepareAndListen() {
        phase = .preparing
        setupTask = Task { [weak self] in
            guard let self else { return }
            guard await Self.requestMicrophone() else {
                self.fail("Microphone access is off. Enable it in Settings to search by voice.")
                return
            }
            do {
                try await self.recognizer.prepare()
                guard !Task.isCancelled, self.phase == .preparing else { return }
                try self.recognizer.start()
                self.phase = .listening
                self.scheduleTimeout()
            } catch {
                guard !Task.isCancelled else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func scheduleTimeout() {
        listenTimeout?.cancel()
        listenTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxListenSeconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func apply(_ events: [TilawaSessionEvent]) {
        guard phase == .listening || phase == .finishing else { return }
        for event in events {
            switch event {
            case let .candidate(surah, ayah):
                if candidate == nil { candidate = TilawaVerseMatch(surah: surah, ayah: ayah, confidence: 0.5) }
            case let .verseMatch(match):
                if !matches.contains(where: { $0.verseKey == match.verseKey }) { matches.append(match) }
            case let .final(verses, alts):
                if !verses.isEmpty { matches = verses }
                let heard = Set(matches.map(\.verseKey))
                alternatives = alts.filter { !heard.contains($0.verseKey) }
                hasFinished = true
                phase = .idle
            }
        }
    }

    private func fail(_ message: String) {
        listenTimeout?.cancel()
        if phase == .listening || phase == .finishing { recognizer.cancel() }
        level = 0
        phase = .failed(message)
    }

    private static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
    }
}
