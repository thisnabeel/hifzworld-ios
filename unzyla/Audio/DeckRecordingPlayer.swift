import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DeckRecordingPlayer {
    static let shared = DeckRecordingPlayer()

    private(set) var activeRecording: DeckRecording?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var playingID: UUID? { activeRecording?.id }
    var isActive: Bool { activeRecording != nil }

    private var player: AVAudioPlayer?
    private var tickTimer: Timer?

    private init() {}

    func toggle(recording: DeckRecording) {
        if activeRecording?.id == recording.id {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }
        play(recording: recording)
    }

    func play(recording: DeckRecording) {
        stop()
        play(url: DeckRecordingStore.shared.fileURL(for: recording), title: recording.displayTitle, id: recording.id, duration: recording.duration, deckID: recording.deckID)
    }

    func play(journal recording: JournalRecording) {
        stop()
        play(
            url: JournalRecordingStore.shared.fileURL(for: recording),
            title: recording.surahNamesLabel.isEmpty ? recording.timestampLabel : recording.surahNamesLabel,
            id: recording.id,
            duration: recording.duration,
            deckID: nil
        )
    }

    private func play(url: URL, title: String, id: UUID, duration: TimeInterval, deckID: UUID?) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)

            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
            activeRecording = DeckRecording(
                id: id,
                deckID: deckID ?? UUID(),
                createdAt: Date(),
                duration: duration > 0 ? duration : audioPlayer.duration,
                title: title,
                fileName: url.lastPathComponent
            )
            self.duration = audioPlayer.duration
            position = 0
            audioPlayer.play()
            isPlaying = true
            startTicker()
        } catch {
            stop()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTicker()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, seconds), max(player.duration, 0))
        player.currentTime = clamped
        position = clamped
    }

    func skip(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    /// Stops playback if the active take belongs to `deckID`.
    func stopIfPlaying(deckID: UUID) {
        guard activeRecording?.deckID == deckID else { return }
        stop()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        player?.stop()
        player = nil
        activeRecording = nil
        isPlaying = false
        position = 0
        duration = 0
    }

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTick()
            }
        }
    }

    private func handleTick() {
        guard let player else { return }
        position = player.currentTime
        duration = player.duration
        if !player.isPlaying {
            isPlaying = false
            if player.currentTime >= player.duration - 0.05 {
                stop()
            }
        }
    }
}
