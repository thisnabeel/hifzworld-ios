import SwiftUI

struct FeedbackTabView: View {
    @Bindable var auth: AuthService
    let onOpenSession: (FeedbackSessionDTO) -> Void

    @State private var sessions: [FeedbackSessionDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    SignInView(auth: auth)
                } else if isLoading && sessions.isEmpty {
                    ProgressView("Loading feedback…")
                } else if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Feedback Yet",
                        systemImage: "text.badge.checkmark",
                        description: Text("Marks from review sessions will appear here.")
                    )
                } else {
                    List(sessions) { session in
                        Button {
                            onOpenSession(session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.bundleTitle)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(session.listener?.displayName ?? "Listener")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("\(session.marks.count) marks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Feedback")
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Sign Out") { auth.signOut() }
                    }
                }
            }
            .task(id: auth.isSignedIn) {
                guard auth.isSignedIn else { return }
                await load()
            }
            .refreshable { await load() }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let remote = try await ReviewSessionService().fetchFeedback()
            #if DEBUG
            sessions = remote.isEmpty ? [FeedbackSessionDTO.stubPreview] : remote
            #else
            sessions = remote
            #endif
        } catch {
            #if DEBUG
            sessions = [FeedbackSessionDTO.stubPreview]
            #else
            errorMessage = error.localizedDescription
            #endif
        }
    }
}

#if DEBUG
extension FeedbackSessionDTO {
    static let stubPreviewID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let stubBundleServerID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static var stubPreview: FeedbackSessionDTO {
        let sessionID = stubPreviewID
        let bundleID = stubBundleServerID
        let listenerID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let reciterID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let now = Date()

        let listener = HifzworldUser(
            id: listenerID,
            email: nil,
            handle: "ustadh",
            displayName: "Ustadh Yusuf",
            avatarURL: nil,
            createdAt: now,
            updatedAt: now
        )

        let marks: [SessionMarkDTO] = [
            SessionMarkDTO(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555501")!,
                reviewSessionID: sessionID,
                mushafBundleID: bundleID,
                listenerID: listenerID,
                listenerDisplayName: listener.displayName,
                wordID: 1,
                verseKey: "2:255",
                pageNumber: 42,
                mushafID: 3,
                markType: MistakeMarkType.tajweed.rawValue,
                note: nil,
                createdAt: now.addingTimeInterval(-120)
            ),
            SessionMarkDTO(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555502")!,
                reviewSessionID: sessionID,
                mushafBundleID: bundleID,
                listenerID: listenerID,
                listenerDisplayName: listener.displayName,
                wordID: 2,
                verseKey: "2:255",
                pageNumber: 42,
                mushafID: 3,
                markType: MistakeMarkType.hesitation.rawValue,
                note: nil,
                createdAt: now.addingTimeInterval(-90)
            ),
            SessionMarkDTO(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555503")!,
                reviewSessionID: sessionID,
                mushafBundleID: bundleID,
                listenerID: listenerID,
                listenerDisplayName: listener.displayName,
                wordID: 3,
                verseKey: "2:286",
                pageNumber: 49,
                mushafID: 3,
                markType: MistakeMarkType.pronunciation.rawValue,
                note: "Slow down on the ending",
                createdAt: now.addingTimeInterval(-30)
            )
        ]

        return FeedbackSessionDTO(
            id: sessionID,
            mushafBundleID: bundleID,
            bundleTitle: "Juz Amma · Sample Deck",
            reciterID: reciterID,
            listenerID: listenerID,
            reciter: nil,
            listener: listener,
            status: "ended",
            startedAt: now.addingTimeInterval(-600),
            endedAt: now,
            markCount: marks.count,
            marks: marks
        )
    }
}
#endif
