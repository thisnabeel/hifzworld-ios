import SwiftUI

struct TaraweehModeView: View {
    @Bindable var reciteVM: ReciteViewModel
    @Bindable var auth: AuthService
    @Bindable var bundleStore: BundleStore

    @Bindable private var planStore = TaraweehPlanStore.shared
    @State private var nights: [TaraweehNightPortion] = []
    @State private var strengthByNight: [Int: Int] = [:]
    @State private var isLoadingStrength = false
    @State private var strengthError: String?

    private var ramadan: IslamicCalendarService.RamadanInfo {
        IslamicCalendarService.ramadanInfo()
    }

    private var isDark: Bool { reciteVM.isDarkMode }

    private var ink: Color { isDark ? .white : .black }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ramadanHeader
                planEditor
                calendarSection
                footnote
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppTheme.pageBackground(dark: isDark).ignoresSafeArea())
        .navigationTitle("Taraweeh")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            planStore.syncMushafID(PreferencesStore.shared.mushafID)
            if reciteVM.juzSegments.isEmpty {
                await reciteVM.loadSegments()
            }
            rebuildNights()
            await loadStrength()
        }
        .onChange(of: planStore.plan.finishNight) { _, _ in
            rebuildNights()
            Task { await loadStrength() }
        }
        .onChange(of: reciteVM.juzSegments.count) { _, _ in
            rebuildNights()
            Task { await loadStrength() }
        }
    }

    private var ramadanHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ramadan \(ramadan.hijriYear) AH")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(ink)

            Text(IslamicCalendarService.formattedGregorianDate(ramadan.startDate))
                .font(.title3)
                .foregroundStyle(ink.opacity(0.7))

            Text(countdownCopy)
                .font(.body.weight(.medium))
                .foregroundStyle(ink.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var countdownCopy: String {
        if let day = ramadan.dayOfRamadan {
            return "Day \(day) of Ramadan"
        }
        if ramadan.daysUntilStart == 0 {
            return "Ramadan begins today"
        }
        let days = ramadan.daysUntilStart
        let daysPart = days == 1 ? "1 day left" : "\(days) days left"
        let months = Int((Double(days) / 30.0).rounded())
        guard months >= 1 else { return daysPart }
        let monthsPart = months == 1 ? "~1 month left" : "~\(months) months left"
        return "\(daysPart) · \(monthsPart)"
    }

    private var planEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leading plan")
                .font(.headline)
                .foregroundStyle(ink)

            HStack(spacing: 8) {
                Text("Finish by night")
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(1)

                Text("\(planStore.plan.finishNight)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(ink)

                Stepper(
                    "Finish night",
                    value: Binding(
                        get: { planStore.plan.finishNight },
                        set: { planStore.updateFinishNight($0) }
                    ),
                    in: TaraweehPlan.minFinishNight...TaraweehPlan.maxFinishNight
                )
                .labelsHidden()

                Spacer(minLength: 4)

                Text(TaraweehPlanBuilder.averageLoadLabel(finishNight: planStore.plan.finishNight))
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    /// Nights laid out like a month calendar, starting on Ramadan’s weekday.
    private var calendarCells: [TaraweehNightPortion?] {
        let cal = Calendar.current
        let firstWeekday = cal.component(.weekday, from: ramadan.startDate)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [TaraweehNightPortion?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: nights.map { Optional($0) })
        while !cells.isEmpty, cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calendar")
                    .font(.headline)
                    .foregroundStyle(ink)
                Spacer()
                if isLoadingStrength {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, night in
                    if let night {
                        nightCell(night)
                    } else {
                        Color.clear
                            .frame(height: 58)
                    }
                }
            }

            if let strengthError {
                Text(strengthError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            legend
        }
    }

    private func nightCell(_ night: TaraweehNightPortion) -> some View {
        let level = strengthByNight[night.night] ?? 0
        let primary = level >= 3 ? Color.white : ink.opacity(0.92)
        let secondary = level >= 3 ? Color.white.opacity(0.8) : ink.opacity(0.55)
        let gregorianDay = Self.gregorianDayNumber(
            forNight: night.night,
            ramadanStart: ramadan.startDate
        )

        return VStack(spacing: 4) {
            Text("\(night.night)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(primary)

            if let gregorianDay {
                Text("\(gregorianDay)")
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundStyle(secondary.opacity(0.7))
            }

            Text(night.cardRangeOneLine)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cellFill(level: level))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ink.opacity(level == 0 ? 0.14 : 0), lineWidth: 1)
        )
        .accessibilityLabel("Night \(night.night), \(night.cardJuzLabel), \(night.pagesLabel), practice level \(level)")
    }

    private static func gregorianDayNumber(forNight night: Int, ramadanStart: Date) -> Int? {
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: night - 1, to: cal.startOfDay(for: ramadanStart)) else {
            return nil
        }
        return cal.component(.day, from: date)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Practice")
                .font(.caption2)
                .foregroundStyle(ink.opacity(0.5))
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(cellFill(level: level))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(ink.opacity(level == 0 ? 0.18 : 0), lineWidth: 1)
                    )
                    .frame(width: 14, height: 14)
            }
            Text("weak → strong")
                .font(.caption2)
                .foregroundStyle(ink.opacity(0.5))
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var footnote: some View {
        Text("Strength reflects your marks and recordings on each night’s pages — not the calendar date you practiced.")
            .font(.caption)
            .foregroundStyle(ink.opacity(0.45))
    }

    private func cellFill(level: Int) -> Color {
        // GitHub-like greens, slightly muted for mushaf chrome.
        let greens: [Color] = [
            Color.clear,
            Color(red: 0.61, green: 0.80, blue: 0.55).opacity(isDark ? 0.45 : 0.55),
            Color(red: 0.35, green: 0.68, blue: 0.40).opacity(isDark ? 0.65 : 0.75),
            Color(red: 0.22, green: 0.55, blue: 0.30),
            Color(red: 0.12, green: 0.40, blue: 0.22),
        ]
        let index = min(4, max(0, level))
        if index == 0 {
            return ink.opacity(isDark ? 0.06 : 0.04)
        }
        return greens[index]
    }

    private func rebuildNights() {
        let mushafID = PreferencesStore.shared.mushafID
        planStore.syncMushafID(mushafID)
        let juz = TaraweehPlanBuilder.juzSegments(mushafID: mushafID, loaded: reciteVM.juzSegments)
        nights = TaraweehPlanBuilder.nights(finishNight: planStore.plan.finishNight, juzSegments: juz)
    }

    private func loadStrength() async {
        isLoadingStrength = true
        strengthError = nil
        defer { isLoadingStrength = false }

        let mushafID = PreferencesStore.shared.mushafID
        let journal = JournalRecordingStore.shared.recordings.filter { $0.mushafID == mushafID }

        var deckHits: [Set<Int>] = []
        for bundle in bundleStore.bundles where bundle.mushafID == mushafID {
            let deckPages = Set(bundle.pageNumbers)
            guard !deckPages.isEmpty else { continue }
            let recordings = DeckRecordingStore.shared.recordings(for: bundle.id)
            for _ in recordings {
                deckHits.append(deckPages)
            }
        }

        var marks: [MushafMarkDTO] = []
        if auth.isSignedIn, let userID = auth.currentUser?.id {
            do {
                marks = try await MushafMarksService().list(
                    subjectID: userID,
                    mushafID: mushafID,
                    limit: 2000
                )
            } catch {
                strengthError = "Couldn’t load marks for practice strength."
            }
        }

        strengthByNight = TaraweehPracticeStrength.levels(
            nights: nights,
            marks: marks,
            journalRecordings: journal,
            deckPageHits: deckHits
        )
    }
}
