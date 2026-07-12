import LiveKit
import SwiftUI

struct VideoCallOverlayView: View {
    @Bindable var video: VideoCallService

    var body: some View {
        if video.isConnected || video.isConnecting {
            Group {
                if video.isMinimized {
                    minimizedBar
                } else {
                    pipWindow
                }
            }
            .padding(12)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var minimizedBar: some View {
        Button {
            video.toggleMinimized()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                Text(video.isConnecting ? "Connecting…" : "Video call")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pipWindow: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                remoteView
                    .frame(width: 160, height: 220)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                localView
                    .frame(width: 56, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                    )
                    .padding(8)
            }

            HStack(spacing: 16) {
                Button {
                    Task { await video.toggleMicrophone() }
                } label: {
                    Image(systemName: video.isMicEnabled ? "mic.fill" : "mic.slash.fill")
                }

                Button {
                    Task { await video.toggleCamera() }
                } label: {
                    Image(systemName: video.isCameraEnabled ? "video.fill" : "video.slash.fill")
                }

                Button {
                    video.toggleMinimized()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }

                Button(role: .destructive) {
                    Task { await video.disconnect() }
                } label: {
                    Image(systemName: "phone.down.fill")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .frame(width: 160)
            .background(Color.black.opacity(0.85))
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 14
                )
            )
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private var remoteView: some View {
        if let track = video.remoteVideoTrack {
            SwiftUIVideoView(track)
                .background(Color.black)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text(video.isConnecting ? "Connecting…" : "Waiting for partner")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var localView: some View {
        if let track = video.localVideoTrack {
            SwiftUIVideoView(track, mirrorMode: .mirror)
        } else {
            Color.gray.opacity(0.4)
        }
    }
}
