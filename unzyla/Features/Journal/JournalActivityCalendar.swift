import SwiftUI

/// Month grid with GitHub/Taraweeh-style activity fills on days that have journal work.
struct JournalActivityCalendar: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    var activityLevel: (Date) -> Int
    var calendar: Calendar = .current

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var daysInGrid: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(monthTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(daysInGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            let newMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: newValue))
                ?? newValue
            if !calendar.isDate(newMonth, equalTo: monthStart, toGranularity: .month) {
                displayedMonth = newMonth
            }
        }
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return false }
        return calendar.startOfDay(for: next) <= todayStart
            || calendar.isDate(next, equalTo: todayStart, toGranularity: .month)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthStart) else { return }
        if delta > 0, !canGoForward { return }
        displayedMonth = next
    }

    private func dayCell(_ date: Date) -> some View {
        let dayStart = calendar.startOfDay(for: date)
        let isFuture = dayStart > todayStart
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let level = isFuture ? 0 : activityLevel(date)
        let ink = Color.primary

        return Button {
            guard !isFuture else { return }
            selectedDate = date
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.body.weight(isSelected || isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(dayForeground(isFuture: isFuture, isSelected: isSelected, level: level))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Circle()
                        .fill(dayFill(isSelected: isSelected, level: level, ink: ink))
                )
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                    } else if isToday, level == 0 {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityLabel(date: date, level: level, isFuture: isFuture))
    }

    private func dayForeground(isFuture: Bool, isSelected: Bool, level: Int) -> Color {
        if isFuture { return Color.secondary.opacity(0.35) }
        if level >= 3 { return .white }
        if isSelected { return Color.accentColor }
        return .primary
    }

    private func dayFill(isSelected: Bool, level: Int, ink: Color) -> Color {
        if level == 0 {
            return isSelected ? Color.accentColor.opacity(0.22) : .clear
        }
        return Self.activityFill(level: level, ink: ink)
    }

    private func accessibilityLabel(date: Date, level: Int, isFuture: Bool) -> String {
        let day = date.formatted(date: .complete, time: .omitted)
        if isFuture { return "\(day), unavailable" }
        if level == 0 { return day }
        return "\(day), activity level \(level)"
    }

    /// Matches Taraweeh calendar greens.
    static func activityFill(level: Int, ink: Color = .primary, isDark: Bool? = nil) -> Color {
        let dark = isDark ?? (UITraitCollection.current.userInterfaceStyle == .dark)
        let greens: [Color] = [
            Color.clear,
            Color(red: 0.61, green: 0.80, blue: 0.55).opacity(dark ? 0.45 : 0.55),
            Color(red: 0.35, green: 0.68, blue: 0.40).opacity(dark ? 0.65 : 0.75),
            Color(red: 0.22, green: 0.55, blue: 0.30),
            Color(red: 0.12, green: 0.40, blue: 0.22),
        ]
        let index = min(4, max(0, level))
        if index == 0 {
            return ink.opacity(dark ? 0.06 : 0.04)
        }
        return greens[index]
    }
}
