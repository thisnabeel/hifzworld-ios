import SwiftUI

struct DeckRecordingsView: View {
    let deckID: UUID
    let deckTitle: String
    let onReview: (DeckRecording) -> Void

    @State private var store = DeckRecordingStore.shared
    @Bindable private var player = DeckRecordingPlayer.shared
    @State private var recordingToRename: DeckRecording?
    @State private var renameText = ""

    private var recordings: [DeckRecording] {
        store.recordings(for: deckID)
    }

    var body: some View {
        List {
            if recordings.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "list.bullet",
                        description: Text("Tap the mic on this deck to record. Previous takes will show up here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Text("Previous recordings for “\(deckTitle)”. Playing a take opens that deck so you can review with its marks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Recordings") {
                    ForEach(recordings) { recording in
                        recordingRow(recording)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if player.playingID == recording.id {
                                        player.stop()
                                    }
                                    store.delete(recording)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Recordings")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Rename Recording",
            isPresented: Binding(
                get: { recordingToRename != nil },
                set: { if !$0 { recordingToRename = nil } }
            )
        ) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { recordingToRename = nil }
            Button("Save") {
                guard var item = recordingToRename else { return }
                item.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                store.save(item)
                recordingToRename = nil
            }
        }
    }

    @ViewBuilder
    private func recordingRow(_ recording: DeckRecording) -> some View {
        HStack(spacing: 12) {
            Button {
                if player.playingID == recording.id {
                    player.togglePlayPause()
                } else {
                    onReview(recording)
                }
            } label: {
                Image(systemName: player.playingID == recording.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.playingID == recording.id && player.isPlaying ? "Pause" : "Play")

            Button {
                onReview(recording)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recording.displayTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(formatDuration(recording.duration))
                        if recording.markCount > 0 {
                            Text("·")
                            Text("\(recording.markCount) mark\(recording.markCount == 1 ? "" : "s")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                recordingToRename = recording
                renameText = recording.title
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rename")
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
