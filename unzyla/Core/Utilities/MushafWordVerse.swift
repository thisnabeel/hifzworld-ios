import Foundation

enum MushafWordVerse {
    private static let ayahMarkerScalar: Unicode.Scalar = "\u{06DF}"
    private static let waqfScalars: Set<Unicode.Scalar> = [
        "\u{06D6}", "\u{06D7}", "\u{06D8}", "\u{06D9}", "\u{06DA}",
        "\u{06DB}", "\u{06DC}", "\u{06E1}", "\u{06E2}",
    ]
    private static let puaMin = 0xF500
    private static let puaMax = 0xF73C

    static func isAyahEndingToken(_ word: MushafWord, mushafID: Int) -> Bool {
        let content = word.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return false }

        if content.unicodeScalars.contains(ayahMarkerScalar) {
            return true
        }

        if content.unicodeScalars.contains(where: { waqfScalars.contains($0) }) {
            return false
        }

        guard mushafID == MushafID.indoPak.rawValue else { return false }

        let coreLength = effectiveWordCharCount(content)
        for scalar in content.unicodeScalars {
            let value = Int(scalar.value)
            if value >= puaMin, value <= puaMax, coreLength == 0 {
                return true
            }
        }
        return false
    }

    static func formattedReference(from ayah: String?) -> String? {
        guard let key = verseKey(from: ayah) else { return nil }
        return "(\(key))"
    }

    static func verseKey(from ayah: String?) -> String? {
        guard let raw = ayah?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let pattern = #"^(\d+)\s*:\s*(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges == 3,
              let surahRange = Range(match.range(at: 1), in: raw),
              let ayahRange = Range(match.range(at: 2), in: raw)
        else {
            return nil
        }
        return "\(raw[surahRange]):\(raw[ayahRange])"
    }

    private static func effectiveWordCharCount(_ text: String) -> Int {
        let normalized = text.decomposedStringWithCompatibilityMapping
        let lettersOnly = normalized.unicodeScalars.filter { scalar in
            scalar.value != 0x0640 && CharacterSet.alphanumerics.contains(scalar)
        }
        return lettersOnly.count
    }
}
