import SwiftUI

struct FeedbackTabView: View {
    @Bindable var auth: AuthService
    let onOpenBundle: (UUID, Int, Int) -> Void

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
                        NavigationLink {
                            FeedbackSessionDetailView(session: session, onOpenMark: onOpenBundle)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.bundleTitle)
                                    .font(.headline)
                                Text(session.listener?.displayName ?? "Listener")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(session.marks.count) marks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            sessions = try await ReviewSessionService().fetchFeedback()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FeedbackSessionDetailView: View {
    let session: FeedbackSessionDTO
    let onOpenMark: (UUID, Int, Int) -> Void

    private var groupedMarks: [(page: Int, marks: [SessionMarkDTO])] {
        let groups = Dictionary(grouping: session.marks, by: \.pageNumber)
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.createdAt ?? .distantPast < $1.createdAt ?? .distantPast }) }
    }

    var body: some View {
        List {
            ForEach(groupedMarks, id: \.page) { group in
                Section("Page \(group.page)") {
                    ForEach(group.marks) { mark in
                        Button {
                            onOpenMark(session.mushafBundleID, mark.pageNumber, mark.wordID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mark.verseKey)
                                    .font(.subheadline.weight(.semibold))
                                Text(mark.markType.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(session.bundleTitle)
    }
}
