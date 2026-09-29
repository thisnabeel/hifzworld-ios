import Foundation

struct ComparisonSegment: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let isDifferent: Bool
}

enum ComparisonEngine {
    private static let diacritics: Set<Character> = ["َ", "ِ", "ُ", "ْ"]

    static func isDiacritic(_ char: Character) -> Bool {
        if diacritics.contains(char) { return true }
        guard let scalar = char.unicodeScalars.first else { return false }
        let code = scalar.value
        return (0x064B...0x065F).contains(code) || code == 0x0670 || code == 0x06E2 || code == 0x06E8
    }

    struct Unit: Hashable {
        let full: String
    }

    static func groupUnits(_ text: String) -> [Unit] {
        var units: [Unit] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            var unit = String(chars[i])
            i += 1
            while i < chars.count, isDiacritic(chars[i]) {
                unit.append(chars[i])
                i += 1
            }
            units.append(Unit(full: unit))
        }
        return units
    }

    static func segments(original: String, variation: String) -> [ComparisonSegment] {
        let units1 = groupUnits(original)
        let units2 = groupUnits(variation)
        let maxLength = max(units1.count, units2.count)

        var differences = Set<Int>()
        for i in 0..<maxLength {
            let u1 = i < units1.count ? units1[i] : nil
            let u2 = i < units2.count ? units2[i] : nil
            if u1?.full != u2?.full {
                differences.insert(i)
            }
        }

        var result: [ComparisonSegment] = []
        var current = ComparisonSegment(text: "", isDifferent: false)

        for i in 0..<units1.count {
            let isDifferent = differences.contains(i)
            if isDifferent != current.isDifferent, !current.text.isEmpty {
                result.append(current)
                current = ComparisonSegment(text: "", isDifferent: isDifferent)
            }
            current = ComparisonSegment(text: current.text + units1[i].full, isDifferent: isDifferent)
        }
        if !current.text.isEmpty {
            result.append(current)
        }
        return result
    }
}
