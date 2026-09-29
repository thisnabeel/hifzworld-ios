import Foundation

enum MushafWordVerse {
    private static let ayahMarkerScalar: Unicode.Scalar = "\u{06DF}"
    private static let waqfScalars: Set<Unicode.Scalar> = [
        "\u{06D6}", "\u{06D7}", "\u{06D8}", "\u{06D9}", "\u{06DA}",
        "\u{06DB}", "\u{06DC}", "\u{06E1}", "\u{06E2}",
    ]
    private static let puaMin = 0xF500
    private static let puaMax = 0xF73C

    /// Location used when creating a mark — prefers a real verse key, otherwise page/line/word.
    struct MarkReference: Equatable {
        let verseKey: String
        let lineNumber: Int?
        let wordPosition: Int?
        let isProvisional: Bool
    }

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

    static func isProvisionalVerseKey(_ key: String) -> Bool {
        key.hasPrefix("p") && key.contains(":l") && key.contains(":w")
    }

    /// Resolve a mark reference for `word` on `page`.
    /// 1) word.ayah  2) inherit from nearby words on the page  3) provisional p/l/w key
    static func markReference(for word: MushafWord, on page: MushafPage, pageNumber: Int) -> MarkReference {
        if let key = verseKey(from: word.ayah) {
            let loc = location(of: word, on: page)
            return MarkReference(
                verseKey: key,
                lineNumber: loc?.line,
                wordPosition: loc?.wordPosition ?? word.position,
                isProvisional: false
            )
        }

        if let inherited = inheritedVerseKey(for: word, on: page) {
            let loc = location(of: word, on: page)
            return MarkReference(
                verseKey: inherited,
                lineNumber: loc?.line,
                wordPosition: loc?.wordPosition ?? word.position,
                isProvisional: false
            )
        }

        let loc = location(of: word, on: page)
        let line = loc?.line ?? 0
        let wordPos = loc?.wordPosition ?? word.position
        let provisional = "p\(pageNumber):l\(line):w\(wordPos)"
        return MarkReference(
            verseKey: provisional,
            lineNumber: loc?.line,
            wordPosition: wordPos,
            isProvisional: true
        )
    }

    private static func location(of word: MushafWord, on page: MushafPage) -> (line: Int, wordPosition: Int)? {
        for line in page.lines {
            if let index = line.words.firstIndex(where: { $0.id == word.id }) {
                return (line.position, line.words[index].position)
            }
        }
        return nil
    }

    /// Walk nearby words on the page for an ayah-bearing neighbor.
    private static func inheritedVerseKey(for word: MushafWord, on page: MushafPage) -> String? {
        guard let lineIndex = page.lines.firstIndex(where: { $0.words.contains(where: { $0.id == word.id }) }) else {
            return nil
        }

        let line = page.lines[lineIndex]
        if let wordIndex = line.words.firstIndex(where: { $0.id == word.id }), wordIndex > 0 {
            for candidate in line.words[..<wordIndex].reversed() {
                if let key = verseKey(from: candidate.ayah) { return key }
            }
        }

        if lineIndex > 0 {
            for earlier in page.lines[..<lineIndex].reversed() {
                for candidate in earlier.words.reversed() {
                    if let key = verseKey(from: candidate.ayah) { return key }
                }
            }
        }

        if let wordIndex = line.words.firstIndex(where: { $0.id == word.id }) {
            for candidate in line.words.suffix(from: wordIndex + 1) {
                if let key = verseKey(from: candidate.ayah) { return key }
            }
        }
        if lineIndex + 1 < page.lines.count {
            for later in page.lines.suffix(from: lineIndex + 1) {
                for candidate in later.words {
                    if let key = verseKey(from: candidate.ayah) { return key }
                }
            }
        }

        return nil
    }

    /// Word IDs to flash when jumping from verse search — the target ayah on this page, through its end marker.
    static func searchHighlightWordIDs(
        on page: MushafPage,
        pageNumber: Int,
        verseKey: String,
        mushafID: Int
    ) -> Set<Int> {
        var ids = Set<Int>()
        for line in page.lines {
            var matchedIndices: [Int] = []
            for (index, word) in line.words.enumerated() {
                let ref = markReference(for: word, on: page, pageNumber: pageNumber)
                if ref.verseKey == verseKey {
                    ids.insert(word.id)
                    matchedIndices.append(index)
                }
            }
            guard let lastIndex = matchedIndices.last else { continue }
            let nextIndex = lastIndex + 1
            if nextIndex < line.words.count {
                let next = line.words[nextIndex]
                if isAyahEndingToken(next, mushafID: mushafID) {
                    ids.insert(next.id)
                }
            }
        }
        return ids
    }

    private static func effectiveWordCharCount(_ text: String) -> Int {
        let normalized = text.decomposedStringWithCompatibilityMapping
        let lettersOnly = normalized.unicodeScalars.filter { scalar in
            scalar.value != 0x0640 && CharacterSet.alphanumerics.contains(scalar)
        }
        return lettersOnly.count
    }
}
