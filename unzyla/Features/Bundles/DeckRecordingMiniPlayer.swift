import SwiftUI

/// Compact playback bar — seeker with handle sits beside the time labels.
struct DeckRecordingMiniPlayer: View {
    @Bindable var player: DeckRecordingPlayer

    var body: some View {
        if let recording = player.activeRecording {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    Text(recording.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        player.skip(by: -10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip back 10 seconds")

                    Button {
                        player.skip(by: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip forward 10 seconds")

                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close player")
                }

                HStack(spacing: 8) {
                    Text(format(player.position))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { player.position },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 0.1)
                    )
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Seek")

                    Text(format(player.duration))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background {
                Rectangle()
                    .fill(.bar)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: -1)
            }
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
