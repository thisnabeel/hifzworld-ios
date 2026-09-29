import SwiftUI

struct JournalTabView: View {
    @Bindable var auth: AuthService

    @State private var selectedDate = Date()
    @State private var entriesByDate: [String: JournalEntryDTO] = [:]
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveNotice: String?
    @State private var dayMarks: [MushafMarkDTO] = []
    @State private var monthMarksByDay: [String: Int] = [:]
    @State private var visibleMonth: Date = Date()
    @Bindable private var recordingStore = JournalRecordingStore.shared
    @Bindable private var player = DeckRecordingPlayer.shared

    private let calendar = Calendar.current

    private var selectedKey: String {
        JournalEntriesService.dateFormatter.string(from: selectedDate)
    }

    private var visibleMonthKey: String {
        let comps = calendar.dateComponents([.year, .month], from: visibleMonth)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    private var selectedStart: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private var isToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    private var isFuture: Bool {
        selectedStart > todayStart
    }

    private var selectedEntry: JournalEntryDTO? {
        entriesByDate[selectedKey]
    }

    var body: some View {
        NavigationStack {
            Group {
                journalContent
            }
            .navigationTitle("Journal")
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Sign Out") { auth.signOut() }
                    }
                }
            }
            .task(id: auth.isSignedIn) {
                guard auth.isSignedIn else { return }
                await loadEntries()
            }
            .task(id: "\(auth.isSignedIn)-\(selectedKey)") {
                await loadMarksForSelectedDay()
            }
            .task(id: "\(auth.isSignedIn)-\(visibleMonthKey)") {
                await loadMarksForVisibleMonth()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.isActive {
                    DeckRecordingMiniPlayer(player: player)
                }
            }
        }
    }

    private var journalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JournalActivityCalendar(
                    selectedDate: $selectedDate,
                    displayedMonth: $visibleMonth,
                    activityLevel: activityLevel(for:),
                    calendar: calendar
                )
                .onChange(of: selectedDate) { _, _ in
                    draft = selectedEntry?.body ?? ""
                    saveNotice = nil
                    errorMessage = nil
                }

                Text(selectedStart.formatted(date: .long, time: .omitted))
                    .font(.headline)

                if isFuture {
                    Text("You can only write on today’s date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !auth.isSignedIn {
                    SignInView(auth: auth)
                        .frame(minHeight: 180)
                }

                daySurahPills
                dayReport

                if !isFuture, auth.isSignedIn {
                    if isToday {
                        todayEditor
                    } else {
                        pastEntry
                    }
                }

                dayRecordings

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .overlay {
            if isLoading && entriesByDate.isEmpty {
                ProgressView("Loading journal…")
            }
        }
    }

    private func activityLevel(for date: Date) -> Int {
        let key = JournalEntriesService.dateFormatter.string(from: date)
        let hasJournal = !(entriesByDate[key]?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let recordings = recordingStore.recordings(on: date, calendar: calendar).count
        let marks = monthMarksByDay[key] ?? 0

        guard hasJournal || recordings > 0 || marks > 0 else { return 0 }

        var score = 0.0
        if hasJournal { score += 1 }
        score += min(2.0, Double(recordings))
        score += min(2.0, Double(marks) / 5.0)
        return min(4, max(1, Int(score.rounded())))
    }

    private var todayEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Journal")
                .font(.headline)
            Text("One entry per day. You can keep editing until midnight in your current time zone.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .frame(minHeight: 180)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                if let saveNotice {
                    Text(saveNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await saveToday() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(selectedEntry == nil ? "Save" : "Update")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    @ViewBuilder
    private var pastEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Journal")
                .font(.headline)
            if let body = selectedEntry?.body, !body.isEmpty {
                Text(body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("No journal on this day.")
                    .foregroundStyle(.secondary)
            }
            Text("Past days are read-only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var daySurahPills: some View {
        let names = JournalDayReport.uniqueSurahNames(
            recordings: recordingStore.recordings(on: selectedDate, calendar: calendar),
            marks: dayMarks
        )
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Surahs")
                    .font(.headline)
                JournalSurahPillFlow(names: names)
            }
        }
    }

    private var dayReport: some View {
        let takes = recordingStore.recordings(on: selectedDate, calendar: calendar)
        let note = selectedEntry?.body
        let text = JournalDayReport.paragraph(
            date: selectedDate,
            recordings: takes,
            marks: dayMarks,
            note: note
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text("Report")
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var dayRecordings: some View {
        let takes = recordingStore.recordings(on: selectedDate, calendar: calendar)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Recordings")
                .font(.headline)
            if takes.isEmpty {
                Text("No recordings on this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(takes) { recording in
                    journalRecordingRow(recording)
                }
            }
        }
    }

    private func journalRecordingRow(_ recording: JournalRecording) -> some View {
        HStack(spacing: 12) {
            Button {
                if player.playingID == recording.id {
                    player.togglePlayPause()
                } else {
                    player.play(journal: recording)
                }
            } label: {
                Image(systemName: player.playingID == recording.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.surahNamesLabel.isEmpty ? "Recording" : recording.surahNamesLabel)
                    .font(.body.weight(.semibold))
                recordingSubtext(recording)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if player.playingID == recording.id {
                    player.stop()
                }
                recordingStore.delete(recording)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete recording")
        }
        .padding(.vertical, 4)
    }

    private func recordingSubtext(_ recording: JournalRecording) -> some View {
        Text("\(recording.timestampLabel) · \(formatDuration(recording.duration)) · \(recording.pagesLabel)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func loadMarksForVisibleMonth() async {
        guard auth.isSignedIn, let userID = auth.currentUser?.id else {
            monthMarksByDay = [:]
            return
        }
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: visibleMonth)
        ) else {
            monthMarksByDay = [:]
            return
        }
        guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: monthEnd))
        else {
            monthMarksByDay = [:]
            return
        }
        do {
            let loaded = try await MushafMarksService().list(
                subjectID: userID,
                from: monthStart,
                to: rangeEnd,
                limit: 2000
            )
            var counts: [String: Int] = [:]
            for mark in loaded where !mark.isUnmarked && !mark.wasUnmarkedWithinAMinute {
                guard let stamped = mark.markedAtOrCreated else { continue }
                let key = JournalEntriesService.dateFormatter.string(from: stamped)
                counts[key, default: 0] += 1
            }
            monthMarksByDay = counts
        } catch {
            // Keep prior month shading if refresh fails.
        }
    }

    private func loadMarksForSelectedDay() async {
        guard auth.isSignedIn, let userID = auth.currentUser?.id else {
            dayMarks = []
            return
        }
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            dayMarks = []
            return
        }
        do {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let loaded = try await MushafMarksService().list(
                subjectID: userID,
                from: start,
                to: end,
                limit: 500
            )
            dayMarks = loaded.filter { !$0.isUnmarked && !$0.wasUnmarkedWithinAMinute }
        } catch {
            dayMarks = []
        }
    }

    private func loadEntries() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let from = calendar.date(byAdding: .year, value: -2, to: Date())
            let response = try await JournalEntriesService().list(from: from, to: Date())
            var map: [String: JournalEntryDTO] = [:]
            for entry in response.journalEntries {
                map[entry.entryDate] = entry
            }
            entriesByDate = map
            selectedDate = Date()
            draft = entriesByDate[selectedKey]?.body ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveToday() async {
        isSaving = true
        errorMessage = nil
        saveNotice = nil
        defer { isSaving = false }
        do {
            let saved: JournalEntryDTO
            if let existing = selectedEntry {
                saved = try await JournalEntriesService().update(id: existing.id, body: draft)
            } else {
                saved = try await JournalEntriesService().upsertToday(body: draft)
            }
            entriesByDate[saved.entryDate] = saved
            draft = saved.body
            saveNotice = "Saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct JournalSurahPillFlow: View {
    let names: [String]

    var body: some View {
        JournalFlowLayout(spacing: 8) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.22))
                    )
            }
        }
    }
}

private struct JournalFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: max(maxX, width), height: y + rowHeight), positions)
    }
}
