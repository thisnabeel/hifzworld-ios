import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

    var onRemotePlay: (() -> Void)?
    var onRemotePause: (() -> Void)?
    var onRemoteToggle: (() -> Void)?
    var onRemoteSeek: ((Double) -> Void)?

    private var artworkTask: URLSessionDataTask?

    private init() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            self?.onRemotePlay?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onRemotePause?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onRemoteToggle?()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onRemoteSeek?(e.positionTime)
            return .success
        }
    }

    func wire(to audio: AudioPlayerService) {
        onRemotePlay = { audio.togglePlayPause() }
        onRemotePause = { audio.togglePlayPause() }
        onRemoteToggle = { audio.togglePlayPause() }
        onRemoteSeek = { audio.seek(to: $0) }
    }

    func update(title: String, artist: String?, durationMillis: Double, positionMillis: Double, playbackRate: Double, artworkURL: String?) {
        artworkTask?.cancel()
        artworkTask = nil

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: durationMillis / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionMillis / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
        ]
        if let artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let artworkURL,
              let url = URL(string: artworkURL),
              url.scheme == "http" || url.scheme == "https"
        else { return }

        artworkTask = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                var merged = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                merged[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = merged
            }
        }
        artworkTask?.resume()
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
