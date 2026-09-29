import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlayerService {
    static let shared = AudioPlayerService()

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var clipEndTime: CMTime?

    var isPlaying = false
    var duration: Double = 0
    var position: Double = 0
    var title: String = ""
    var artist: String = ""
    var artworkURL: String?

    private init() {
        configureSession()
    }

    func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    func playClip(url: URL, start: Double, end: Double, title: String, artist: String? = nil, artworkURL: String? = nil) {
        stop()
        self.title = title
        self.artist = artist ?? ""
        self.artworkURL = artworkURL

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        clipEndTime = CMTime(seconds: end, preferredTimescale: 600)
        duration = end - start
        position = 0
        isPlaying = true

        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()

        addObservers(start: start)
        NowPlayingController.shared.update(
            title: title,
            artist: artist,
            durationMillis: duration * 1000,
            positionMillis: 0,
            playbackRate: 1,
            artworkURL: artworkURL
        )
    }

    func playFullTrack(url: URL, title: String, artist: String?, artworkURL: String?) {
        stop()
        self.title = title
        self.artist = artist ?? ""
        self.artworkURL = artworkURL
        clipEndTime = nil

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        isPlaying = true

        Task {
            if let duration = try? await item.asset.load(.duration) {
                self.duration = duration.seconds
            }
            addObservers(start: 0)
            player?.play()
            NowPlayingController.shared.update(
                title: title,
                artist: artist,
                durationMillis: duration * 1000,
                positionMillis: 0,
                playbackRate: 1,
                artworkURL: artworkURL
            )
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        NowPlayingController.shared.update(
            title: title,
            artist: artist.isEmpty ? nil : artist,
            durationMillis: duration * 1000,
            positionMillis: position * 1000,
            playbackRate: isPlaying ? 1 : 0,
            artworkURL: artworkURL
        )
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        position = seconds
    }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        endObserver = nil
        timeObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        position = 0
        duration = 0
        clipEndTime = nil
        NowPlayingController.shared.clear()
    }

    private func addObservers(start: Double) {
        guard let player else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.position = max(0, time.seconds - start)
                if let clipEnd = self.clipEndTime, time >= clipEnd {
                    self.stop()
                    return
                }
                NowPlayingController.shared.update(
                    title: self.title,
                    artist: self.artist.isEmpty ? nil : self.artist,
                    durationMillis: self.duration * 1000,
                    positionMillis: self.position * 1000,
                    playbackRate: self.isPlaying ? 1 : 0,
                    artworkURL: self.artworkURL
                )
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }
}
