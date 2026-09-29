import Foundation

enum JournalDayReport {
    static func paragraph(
        date: Date,
        recordings: [JournalRecording],
        marks: [MushafMarkDTO],
        note: String?
    ) -> String {
        let takes = recordings.sorted { $0.createdAt < $1.createdAt }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let markCounts = counts(from: marks)
        let hasRecordings = !takes.isEmpty
        let hasMarks = markCounts.contains { $0.value > 0 }
        let hasNote = !trimmedNote.isEmpty

        guard hasRecordings || hasMarks || hasNote else {
            return "Nothing logged this day."
        }

        let day = dayLabel(date)
        var sentences: [String] = []

        if hasRecordings {
            sentences.append("On \(day) you recorded \(recordingClause(takes, marks: marks)).")
        }

        if hasMarks {
            let clause = markClause(markCounts)
            if hasRecordings {
                sentences.append("You marked \(clause).")
            } else {
                sentences.append("On \(day) you marked \(clause).")
            }
        }

        if hasNote {
            if sentences.isEmpty {
                sentences.append("On \(day) you wrote: “\(trimmedNote)”.")
            } else {
                sentences.append("You wrote: “\(trimmedNote)”.")
            }
        }

        return sentences.joined(separator: " ")
    }

    private static func recordingClause(_ takes: [JournalRecording], marks: [MushafMarkDTO]) -> String {
        let count = takes.count
        let takeWord = count == 1 ? "1 take" : "\(count) takes"
        let total = takes.reduce(0) { $0 + $1.duration }
        var parts = ["\(takeWord) (\(formatDuration(total)))"]

        let surahs = uniqueSurahNames(recordings: takes, marks: marks)
        if !surahs.isEmpty {
            parts.append("in \(joinList(surahs))")
        }

        let pages = takes.flatMap(\.pageNumbers)
        let pagesText = collapsedPages(pages)
        if !pagesText.isEmpty {
            parts.append(pagesText)
        }

        return parts.joined(separator: ", ")
    }

    private static func markClause(_ counts: [MistakeMarkType: Int]) -> String {
        var bits: [String] = []
        for type in MistakeMarkType.allCases {
            let n = counts[type] ?? 0
            guard n > 0 else { continue }
            let noun: String
            switch type {
            case .mistake:
                noun = n == 1 ? "mistake" : "mistakes"
            case .tajweed:
                noun = n == 1 ? "tajweed" : "tajweed"
            }
            bits.append("\(n) \(noun)")
        }
        return joinList(bits)
    }

    private static func counts(from marks: [MushafMarkDTO]) -> [MistakeMarkType: Int] {
        var map: [MistakeMarkType: Int] = [:]
        for mark in marks {
            let type = MistakeMarkType.resolved(from: mark.markType)
            map[type, default: 0] += 1
        }
        return map
    }

    static func uniqueSurahNames(recordings: [JournalRecording], marks: [MushafMarkDTO]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for recording in recordings.sorted(by: { $0.createdAt < $1.createdAt }) {
            for name in recording.surahNames where seen.insert(name).inserted {
                names.append(name)
            }
        }
        for mark in marks {
            guard let number = BundlePageGrouping.resolvedSurahNumber(for: mark.pageNumber, overrides: [:]) else {
                continue
            }
            let name = BundlePageGrouping.englishName(forSurahNumber: number)
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    private static func collapsedPages(_ pages: [Int]) -> String {
        let sorted = Array(Set(pages)).sorted()
        guard !sorted.isEmpty else { return "" }
        if sorted.count == 1 { return "p. \(sorted[0])" }
        var parts: [String] = []
        var start = sorted[0]
        var prev = sorted[0]
        for page in sorted.dropFirst() {
            if page == prev + 1 {
                prev = page
                continue
            }
            parts.append(start == prev ? "\(start)" : "\(start)–\(prev)")
            start = page
            prev = page
        }
        parts.append(start == prev ? "\(start)" : "\(start)–\(prev)")
        return "p. " + parts.joined(separator: ", ")
    }

    private static func joinList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items[items.count - 1])"
        }
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
