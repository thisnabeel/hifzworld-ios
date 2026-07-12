import Foundation
import LiveKit
import Observation

@MainActor
@Observable
final class VideoCallService {
    static let shared = VideoCallService()

    private(set) var room: Room?
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isMinimized = false
    private(set) var errorMessage: String?
    private(set) var remoteVideoTrack: (any VideoTrack)?
    private(set) var localVideoTrack: (any VideoTrack)?
    private(set) var isMicEnabled = true
    private(set) var isCameraEnabled = true

    private init() {}

    func connect(url: String, token: String) async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let room = Room()
            try await room.connect(url: url, token: token)
            try await room.localParticipant.setCamera(enabled: true)
            try await room.localParticipant.setMicrophone(enabled: true)

            self.room = room
            self.isConnected = true
            self.isCameraEnabled = true
            self.isMicEnabled = true
            self.localVideoTrack = room.localParticipant.firstCameraVideoTrack
            refreshRemoteTrack()

            room.add(delegate: self)
        } catch {
            errorMessage = error.localizedDescription
            await disconnect()
        }
    }

    func disconnect() async {
        room?.remove(delegate: self)
        await room?.disconnect()
        room = nil
        isConnected = false
        isMinimized = false
        remoteVideoTrack = nil
        localVideoTrack = nil
    }

    func toggleMinimized() {
        isMinimized.toggle()
    }

    func toggleCamera() async {
        guard let room else { return }
        let next = !isCameraEnabled
        do {
            try await room.localParticipant.setCamera(enabled: next)
            isCameraEnabled = next
            localVideoTrack = room.localParticipant.firstCameraVideoTrack
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleMicrophone() async {
        guard let room else { return }
        let next = !isMicEnabled
        do {
            try await room.localParticipant.setMicrophone(enabled: next)
            isMicEnabled = next
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshRemoteTrack() {
        guard let room else {
            remoteVideoTrack = nil
            return
        }
        for participant in room.remoteParticipants.values {
            if let track = participant.firstCameraVideoTrack {
                remoteVideoTrack = track
                return
            }
        }
        remoteVideoTrack = nil
    }
}

extension VideoCallService: RoomDelegate {
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            refreshRemoteTrack()
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            refreshRemoteTrack()
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            refreshRemoteTrack()
        }
    }
}
