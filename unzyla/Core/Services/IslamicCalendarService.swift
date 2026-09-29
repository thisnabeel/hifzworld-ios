import Foundation

enum IslamicCalendarService {
    private static var hijri: Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = .current
        return calendar
    }

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Ramadan status relative to `date` (default: now).
    struct RamadanInfo: Equatable {
        let hijriYear: Int
        let startDate: Date
        let endDate: Date
        /// Positive before Ramadan, 0 on start day, negative after start while still in Ramadan for day-of, etc.
        let daysUntilStart: Int
        let dayOfRamadan: Int?
        let hasEnded: Bool

        var isUpcoming: Bool { daysUntilStart > 0 }
        var isActive: Bool { dayOfRamadan != nil }
    }

    static func ramadanInfo(on date: Date = Date()) -> RamadanInfo {
        let today = gregorian.startOfDay(for: date)
        let comps = hijri.dateComponents([.year, .month, .day], from: today)
        let year = comps.year ?? 1
        let month = comps.month ?? 1

        if month == 9, let day = comps.day {
            let start = ramadanStart(hijriYear: year) ?? today
            let end = ramadanEnd(hijriYear: year) ?? today
            return RamadanInfo(
                hijriYear: year,
                startDate: start,
                endDate: end,
                daysUntilStart: 0,
                dayOfRamadan: day,
                hasEnded: false
            )
        }

        if month > 9 {
            // This year's Ramadan already passed — look at next year.
            let nextYear = year + 1
            let start = ramadanStart(hijriYear: nextYear) ?? today
            let end = ramadanEnd(hijriYear: nextYear) ?? start
            let days = gregorian.dateComponents([.day], from: today, to: gregorian.startOfDay(for: start)).day ?? 0
            return RamadanInfo(
                hijriYear: nextYear,
                startDate: start,
                endDate: end,
                daysUntilStart: max(0, days),
                dayOfRamadan: nil,
                hasEnded: false
            )
        }

        // Months 1–8: upcoming Ramadan this Hijri year.
        let start = ramadanStart(hijriYear: year) ?? today
        let end = ramadanEnd(hijriYear: year) ?? start
        let days = gregorian.dateComponents([.day], from: today, to: gregorian.startOfDay(for: start)).day ?? 0
        return RamadanInfo(
            hijriYear: year,
            startDate: start,
            endDate: end,
            daysUntilStart: max(0, days),
            dayOfRamadan: nil,
            hasEnded: false
        )
    }

    static func ramadanStart(hijriYear: Int) -> Date? {
        var comps = DateComponents()
        comps.year = hijriYear
        comps.month = 9
        comps.day = 1
        guard let date = hijri.date(from: comps) else { return nil }
        return gregorian.startOfDay(for: date)
    }

    static func ramadanEnd(hijriYear: Int) -> Date? {
        // Last day of Ramadan: day before Shawwal 1.
        var comps = DateComponents()
        comps.year = hijriYear
        comps.month = 10
        comps.day = 1
        guard let shawwal = hijri.date(from: comps) else { return nil }
        guard let last = gregorian.date(byAdding: .day, value: -1, to: shawwal) else { return nil }
        return gregorian.startOfDay(for: last)
    }

    static func formattedGregorianDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.locale = .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
