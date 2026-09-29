import SwiftUI

struct FeedbackTabView: View {
    @Bindable var auth: AuthService
    var bundleStore: BundleStore
    @Bindable var reciteVM: ReciteViewModel
    var onOpenMushafMark: ((MushafMarkDTO, Set<Int>) -> Void)?

    @State private var marks: [MushafMarkDTO] = []
    @State private var friends: [HifzworldUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var filterMarkerID: UUID?
    @State private var filterDeckID: UUID?
    @State private var filterPageText = ""
    @State private var filterFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var filterTo = Date()
    @State private var useDateFilter = false
    @State private var quickDatePreset: QuickDatePreset = .none
    /// `nil` means All. Used when Today / Yesterday / This week is selected.
    @State private var selectedSurahNumber: Int?
    @State private var showPopQuiz = false

    private enum QuickDatePreset: String, CaseIterable, Identifiable {
        case none
        case today
        case yesterday
        case thisWeek

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "Any time"
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "This week"
            }
        }
    }

    private var viewingAsFriend: HifzworldUser? {
        guard reciteVM.isCoachingFriend else { return nil }
        return reciteVM.coachSubject
    }

    private var viewingAsLabel: String {
        guard let friend = viewingAsFriend else { return "" }
        return friend.handle.map { "@\($0)" } ?? friend.displayName
    }

    /// Marks subject: friend when viewing as them, otherwise self.
    private var feedbackSubjectID: UUID? {
        viewingAsFriend?.id ?? auth.currentUser?.id
    }

    private var markerFilterOptions: [HifzworldUser] {
        if let friend = viewingAsFriend {
            var options: [HifzworldUser] = []
            if let me = auth.currentUser { options.append(me) }
            options.append(friend)
            return options
        }
        return friends
    }

    private var decks: [MushafBundle] {
        bundleStore.bundles.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var selectedDeck: MushafBundle? {
        guard let filterDeckID else { return nil }
        return bundleStore.bundle(id: filterDeckID)
    }

    private var showsSurahTabs: Bool {
        switch quickDatePreset {
        case .today, .yesterday, .thisWeek: return true
        case .none: return false
        }
    }

    private struct SurahTabItem: Identifiable {
        let number: Int
        let title: String
        var id: Int { number }
    }

    private var surahTabs: [SurahTabItem] {
        var seen = Set<Int>()
        var tabs: [SurahTabItem] = []
        for mark in marks {
            guard let number = surahNumber(for: mark), !seen.contains(number) else { continue }
            seen.insert(number)
            tabs.append(SurahTabItem(number: number, title: surahTitle(for: mark) ?? "Surah \(number)"))
        }
        return tabs.sorted { $0.number < $1.number }
    }

    private var displayedMarks: [MushafMarkDTO] {
        guard showsSurahTabs, let selectedSurahNumber else { return marks }
        return marks.filter { surahNumber(for: $0) == selectedSurahNumber }
    }

    private var filterStamp: String {
        [
            feedbackSubjectID?.uuidString ?? "",
            filterMarkerID?.uuidString ?? "",
            filterDeckID?.uuidString ?? "",
            filterPageText.trimmingCharacters(in: .whitespacesAndNewlines),
            useDateFilter ? "1" : "0",
            quickDatePreset.rawValue,
            String(filterFrom.timeIntervalSince1970),
            String(filterTo.timeIntervalSince1970),
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewingAsFriend != nil {
                ViewingAsBanner(label: viewingAsLabel) {
                    reciteVM.exitCoachMode()
                }
            }

            NavigationStack {
                Group {
                    if !auth.isSignedIn {
                        SignInView(auth: auth)
                    } else if isLoading && marks.isEmpty {
                        ProgressView("Loading marks…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if marks.isEmpty && isDefaultFilterState {
                        emptyMarksGuide
                    } else {
                        marksList
                    }
                }
                .navigationTitle("Marks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if auth.isSignedIn {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Pop Quiz") {
                                showPopQuiz = true
                            }
                            .disabled(displayedMarks.isEmpty)
                        }
                    }
                }
                .fullScreenCover(isPresented: $showPopQuiz) {
                    PopQuizSheet(marks: displayedMarks, isDarkMode: reciteVM.isDarkMode)
                }
                .task(id: auth.isSignedIn) {
                    guard auth.isSignedIn else { return }
                    await loadFriends()
                }
                .task(id: filterStamp) {
                    guard auth.isSignedIn else { return }
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await loadMarks()
                }
                .onChange(of: viewingAsFriend?.id) { _, _ in
                    filterMarkerID = nil
                    filterDeckID = nil
                }
                .refreshable { await loadMarks() }
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
    }

    private var isDefaultFilterState: Bool {
        filterMarkerID == nil
            && filterDeckID == nil
            && filterPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !useDateFilter
            && quickDatePreset == .none
            && selectedSurahNumber == nil
    }

    private var emptyMarksGuide: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checklist")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)

                VStack(spacing: 8) {
                    Text("No Marks Yet")
                        .font(.title2.bold())
                    Text("Marks you and your friends leave on the Mushaf show up here so you can review and quiz yourself.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Mark on the Mushaf")
                        .font(.headline)

                    Text("Open the Mushaf tab, tap the pencil, then tap words to mark mistakes. Use Next / Prev mistake to jump between them, and invert to focus on what you marked.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image("GuideMarksEmpty")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .accessibilityLabel("Screenshot of marking tools on the Mushaf")

                    Text("Come back to Marks to filter by friend or deck, and run Pop Quiz from your marks.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var marksList: some View {
        List {
            Section {
                Picker("Marked by", selection: $filterMarkerID) {
                    Text("Anyone").tag(UUID?.none)
                    if viewingAsFriend == nil, let me = auth.currentUser {
                        Text("Me").tag(Optional(me.id))
                    }
                    ForEach(markerFilterOptions) { person in
                        Text(markerFilterLabel(person)).tag(Optional(person.id))
                    }
                }

                Picker("Deck", selection: $filterDeckID) {
                    Text("Any deck").tag(UUID?.none)
                    ForEach(decks) { deck in
                        Text(deck.title).tag(Optional(deck.id))
                    }
                }

                TextField("Page (optional)", text: $filterPageText)
                    .keyboardType(.numberPad)

                VStack(alignment: .leading, spacing: 10) {
                    Text("When")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    quickDateButtons
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Toggle("Custom date range", isOn: Binding(
                    get: { useDateFilter && quickDatePreset == .none },
                    set: { enabled in
                        if enabled {
                            quickDatePreset = .none
                            useDateFilter = true
                        } else if quickDatePreset == .none {
                            useDateFilter = false
                        }
                    }
                ))
                if useDateFilter, quickDatePreset == .none {
                    DatePicker("From", selection: $filterFrom, displayedComponents: .date)
                    DatePicker("To", selection: $filterTo, displayedComponents: .date)
                }
            } header: {
                Text("Filters")
            } footer: {
                if let selectedDeck {
                    Text("Deck filter shows marks on pages in “\(selectedDeck.title)”.")
                }
            }

            if showsSurahTabs, !marks.isEmpty {
                Section {
                    surahTabButtons
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                } header: {
                    Text("Surah")
                }
            }

            Section("Marks") {
                if displayedMarks.isEmpty {
                    Text("No marks match these filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedMarks) { mark in
                        Button {
                            onOpenMushafMark?(mark, Set(displayedMarks.map(\.pageNumber)))
                        } label: {
                            markRow(mark)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var surahTabButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                surahChip(title: "All", isSelected: selectedSurahNumber == nil) {
                    selectedSurahNumber = nil
                }
                ForEach(surahTabs) { tab in
                    surahChip(title: tab.title, isSelected: selectedSurahNumber == tab.number) {
                        selectedSurahNumber = tab.number
                    }
                }
            }
        }
    }

    private func surahChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    private var quickDateButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickDatePreset.allCases) { preset in
                    Button {
                        applyQuickDatePreset(preset)
                    } label: {
                        Text(preset.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(quickDatePreset == preset ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(quickDatePreset == preset ? Color.accentColor.opacity(0.22) : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func markRow(_ mark: MushafMarkDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(surahTitle(for: mark) ?? "Pg. \(mark.pageNumber)")
                    .font(.headline)
                Spacer()
                Text(mark.markType.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(pageReferenceLine(for: mark))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if mark.isFromLiveReview {
                Label("Live review", systemImage: "headphones")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            HStack {
                Text(markerLabel(mark))
                Spacer()
                if let markedAt = mark.markedAtOrCreated {
                    Text(relativeMinuteLabel(markedAt))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }

    private func personLabel(_ user: HifzworldUser) -> String {
        user.handle.map { "@\($0)" } ?? user.displayName
    }

    private func markerFilterLabel(_ user: HifzworldUser) -> String {
        if let me = auth.currentUser, user.id == me.id {
            return "Me"
        }
        return personLabel(user)
    }

    private func surahNumber(for mark: MushafMarkDTO) -> Int? {
        if !MushafWordVerse.isProvisionalVerseKey(mark.verseKey),
           let head = mark.verseKey.split(separator: ":").first {
            let trimmed = String(head).trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Int(trimmed), (1...114).contains(number) {
                return number
            }
        }
        return BundlePageGrouping.defaultSurahNumber(for: mark.pageNumber)
    }

    private func surahTitle(for mark: MushafMarkDTO) -> String? {
        guard let number = surahNumber(for: mark) else { return nil }
        let english = SurahMeta.englishName(number)
        if !english.isEmpty { return english }
        return BundlePageGrouping.englishName(forSurahNumber: number)
    }

    private func pageReferenceLine(for mark: MushafMarkDTO) -> String {
        if MushafWordVerse.isProvisionalVerseKey(mark.verseKey) {
            if let line = mark.lineNumber, let word = mark.wordPosition {
                return "Pg. \(mark.pageNumber) · L\(line) · W\(word)"
            }
            return "Pg. \(mark.pageNumber)"
        }
        return "Pg. \(mark.pageNumber) · \(mark.displayReference)"
    }

    private func markerLabel(_ mark: MushafMarkDTO) -> String {
        let meID = auth.currentUser?.id
        let subject = viewingAsFriend

        if let meID, mark.markerID == meID {
            return "You"
        }
        if let subject, mark.markerID == subject.id {
            return personLabel(subject)
        }
        // While viewing as someone, hide other markers' identities.
        if subject != nil {
            return "Someone"
        }

        if let handle = mark.marker?.handle {
            return "@\(handle)"
        }
        return mark.marker?.displayName ?? "Someone"
    }

    private func applyQuickDatePreset(_ preset: QuickDatePreset) {
        quickDatePreset = preset
        selectedSurahNumber = nil
        let calendar = Calendar.current
        let now = Date()

        switch preset {
        case .none:
            useDateFilter = false
        case .today:
            useDateFilter = true
            filterFrom = calendar.startOfDay(for: now)
            filterTo = now
        case .yesterday:
            useDateFilter = true
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            filterFrom = calendar.startOfDay(for: yesterday)
            filterTo = yesterday
        case .thisWeek:
            useDateFilter = true
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            filterFrom = weekStart
            filterTo = now
        }
    }

    /// Show marks immediately. Hide if unmarked — including accidental add+undo within a minute.
    private func shouldShowMark(_ mark: MushafMarkDTO) -> Bool {
        let pendingDeleteWordIDs = Set(
            PendingMushafMarksStore.shared.items
                .filter { $0.kind == .delete }
                .map(\.wordID)
        )
        if pendingDeleteWordIDs.contains(mark.wordID) {
            return false
        }
        if mark.wasUnmarkedWithinAMinute {
            return false
        }
        if mark.isUnmarked {
            return false
        }
        return true
    }

    private func relativeMinuteLabel(_ date: Date) -> String {
        let minutes = max(1, Int((Date().timeIntervalSince(date) / 60).rounded()))
        if minutes < 60 {
            return "~\(minutes) min ago"
        }
        let hours = max(1, Int((Double(minutes) / 60).rounded()))
        if hours < 24 {
            return "~\(hours) hr ago"
        }
        let days = max(1, Int((Double(hours) / 24).rounded()))
        return "~\(days) day\(days == 1 ? "" : "s") ago"
    }

    private func historicalLiveReviewMarks(
        alreadyLoaded: [MushafMarkDTO],
        subjectID: UUID
    ) async -> [MushafMarkDTO] {
        let existingWordIDs = Set(alreadyLoaded.map(\.wordID))
        do {
            let sessions = try await ReviewSessionService().fetchFeedback()
            return sessions
                .filter { $0.reciterID == subjectID }
                .flatMap(\.marks)
                .filter { !$0.isUnmarked && !existingWordIDs.contains($0.wordID) }
                .map { mark in
                    mushafMark(from: mark, reciterID: subjectID)
                }
        } catch {
            return []
        }
    }

    private func mushafMark(from sessionMark: SessionMarkDTO, reciterID: UUID) -> MushafMarkDTO {
        MushafMarkDTO(
            id: sessionMark.id,
            subjectID: reciterID,
            markerID: sessionMark.listenerID,
            subject: nil,
            marker: HifzworldUser(
                id: sessionMark.listenerID,
                email: nil,
                handle: nil,
                displayName: sessionMark.listenerDisplayName ?? "Listener",
                avatarURL: nil,
                createdAt: nil,
                updatedAt: nil
            ),
            wordID: sessionMark.wordID,
            verseKey: sessionMark.verseKey,
            pageNumber: sessionMark.pageNumber,
            lineNumber: sessionMark.lineNumber,
            wordPosition: sessionMark.wordPosition,
            mushafID: sessionMark.mushafID,
            markType: sessionMark.markType,
            note: MushafMarkDTO.liveReviewNote,
            createdAt: sessionMark.createdAt,
            updatedAt: nil,
            markedAt: sessionMark.markedAt ?? sessionMark.createdAt,
            unmarkedAt: sessionMark.unmarkedAt,
            heatsCount: nil
        )
    }

    private func loadFriends() async {
        do {
            let response = try await FriendsService().list()
            friends = response.friends.compactMap(\.user)
        } catch {
            friends = []
        }
    }

    private func loadMarks() async {
        guard let subjectID = feedbackSubjectID else {
            marks = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        let page = Int(filterPageText.trimmingCharacters(in: .whitespacesAndNewlines))
        let calendar = Calendar.current
        let from = useDateFilter ? calendar.startOfDay(for: filterFrom) : nil
        let to: Date? = useDateFilter
            ? calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: filterTo))
            : nil

        do {
            var loaded = try await MushafMarksService().list(
                subjectID: subjectID,
                markerID: filterMarkerID,
                page: page,
                from: from,
                to: to,
                limit: 300
            )

            if let deck = selectedDeck {
                let pages = Set(deck.pageNumbers)
                loaded = loaded.filter {
                    pages.contains($0.pageNumber) && $0.mushafID == deck.mushafID
                }
            }

            loaded.append(contentsOf: await historicalLiveReviewMarks(alreadyLoaded: loaded, subjectID: subjectID))
            loaded = loaded.filter { shouldShowMark($0) }

            marks = loaded
            if let selected = selectedSurahNumber,
               !loaded.contains(where: { surahNumber(for: $0) == selected }) {
                selectedSurahNumber = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            marks = []
        }
    }
}
