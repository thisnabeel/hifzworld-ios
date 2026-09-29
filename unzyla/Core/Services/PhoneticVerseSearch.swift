import Foundation
import SwiftUI

struct PhoneticVerseHit: Identifiable, Hashable {
    var id: String { verseKey }
    let verseKey: String
    let transliteration: String
    let arabic: String
    let page: Int?
    let score: Double
    /// Raw transliteration word indices matched by the query (inclusive lower, exclusive upper).
    let matchWordRange: Range<Int>?

    var transliterationSnippet: String {
        PhoneticVerseSearch.snippetWindow(
            transliteration,
            aroundWords: matchWordRange,
            maxChars: 110
        ).display
    }

    var arabicSnippet: String {
        PhoneticVerseSearch.snippetWindow(
            arabic,
            aroundWords: matchWordRange,
            maxChars: 90
        ).display
    }
}

/// Offline phonetic / transliteration search over a bundled Tanzil-style ayah index.
enum PhoneticVerseSearch {
    private static let lock = NSLock()
    private static var cachedEntries: [Entry]?

    private struct IndexFile: Decodable {
        let ayahs: [AyahRow]
    }

    private struct AyahRow: Decodable {
        let k: String
        let t: String
        let a: String
        let p2: Int?
        let p3: Int?
    }

    private struct Entry {
        let verseKey: String
        let transliteration: String
        let arabic: String
        let pageIndoPak: Int?
        let pageUthmani: Int?
        let normalized: String
        let tokens: [String]
    }

    static func search(query: String, mushafID: Int, limit: Int = 12) -> [PhoneticVerseHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let direct = parseVerseKey(trimmed) {
            return entries()
                .filter { $0.verseKey == direct }
                .prefix(limit)
                .map { hit(from: $0, mushafID: mushafID, score: 10_000, matchWordRange: nil) }
        }

        let queryTokens = tokenize(normalize(trimmed))
        guard !queryTokens.isEmpty else { return [] }

        let joinedQuery = queryTokens.joined(separator: " ")
        var scored: [(Entry, Double, Range<Int>?)] = []

        for entry in entries() {
            let match = matchDetails(entry: entry, queryTokens: queryTokens, joinedQuery: joinedQuery)
            guard let match else { continue }
            scored.append((entry, match.score, match.wordRange))
        }

        scored.sort { lhs, rhs in
            let left = verseParts(lhs.0.verseKey)
            let right = verseParts(rhs.0.verseKey)
            if left.surah != right.surah { return left.surah < right.surah }
            if left.ayah != right.ayah { return left.ayah < right.ayah }
            return lhs.1 > rhs.1
        }

        return scored.prefix(limit).map {
            hit(from: $0.0, mushafID: mushafID, score: $0.1, matchWordRange: $0.2)
        }
    }

    static func looksLikePhoneticQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if parseVerseKey(trimmed) != nil { return true }
        return trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    // MARK: - Scoring

    private struct MatchDetails {
        let score: Double
        let wordRange: Range<Int>?
    }

    private static func matchDetails(
        entry: Entry,
        queryTokens: [String],
        joinedQuery: String
    ) -> MatchDetails? {
        if entry.normalized == joinedQuery {
            return MatchDetails(score: 5_000, wordRange: 0..<entry.tokens.count)
        }
        if let phrase = consecutiveTokenMatch(haystack: entry.tokens, needle: queryTokens) {
            return MatchDetails(score: phrase.score, wordRange: phrase.range)
        }
        if entry.normalized.hasPrefix(joinedQuery + " ") || entry.normalized.contains(" " + joinedQuery + " ")
            || entry.normalized.hasSuffix(" " + joinedQuery) || entry.normalized.contains(joinedQuery) {
            let coverage = Double(joinedQuery.count) / Double(max(entry.normalized.count, 1))
            let score = 2_000 + coverage * 500 + Double(queryTokens.count) * 40
            return MatchDetails(score: score, wordRange: firstContainingRange(in: entry.tokens, queryTokens: queryTokens))
        }

        let entrySet = Set(entry.tokens)
        let hits = queryTokens.filter { token in
            entrySet.contains(token) || entry.tokens.contains { $0.hasPrefix(token) && token.count >= 3 }
        }
        guard hits.count == queryTokens.count, !queryTokens.isEmpty else { return nil }
        return MatchDetails(
            score: Double(hits.count) * 30,
            wordRange: firstContainingRange(in: entry.tokens, queryTokens: queryTokens)
        )
    }

    private static func firstContainingRange(in haystack: [String], queryTokens: [String]) -> Range<Int>? {
        consecutiveTokenMatch(haystack: haystack, needle: queryTokens)?.range
            ?? haystack.firstIndex(where: { token in
                queryTokens.contains { token == $0 || (token.hasPrefix($0) && $0.count >= 3) }
            }).map { $0..<($0 + 1) }
    }

    /// Highest score for a consecutive token sequence match.
    /// Allows fusing query tokens (`wa`+`law` → `walaw`) to match Tanzil glued particles.
    private static func consecutiveTokenMatch(
        haystack: [String],
        needle: [String]
    ) -> (score: Double, range: Range<Int>)? {
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        var best: (score: Double, range: Range<Int>)?
        for start in 0..<haystack.count {
            var h = start
            var n = 0
            var fusedUsed = 0
            while n < needle.count && h < haystack.count {
                let hay = haystack[h]
                let need = needle[n]
                if hay == need {
                    h += 1
                    n += 1
                    continue
                }
                // Last query token may be a prefix of the haystack token.
                if n == needle.count - 1, need.count >= 3, hay.hasPrefix(need) {
                    h += 1
                    n += 1
                    continue
                }
                // Fuse 2–3 query tokens to match one haystack token (wa+law → walaw).
                var fused = need
                var take = 1
                var matched = false
                while take < 3, n + take < needle.count {
                    fused += needle[n + take]
                    take += 1
                    if hay == fused || (take == 2 && hay.hasPrefix(fused) && fused.count >= 4) {
                        matched = true
                        break
                    }
                }
                if matched {
                    fusedUsed += take - 1
                    h += 1
                    n += take
                    continue
                }
                break
            }
            guard n == needle.count else { continue }
            let score = 1_000 + Double(needle.count) * 80 - Double(start) * 0.01 - Double(fusedUsed) * 0.1
            let range = start..<h
            if best == nil || score > best!.score {
                best = (score, range)
            }
        }
        return best
    }

    // MARK: - Normalization

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()

        // Arabizi: 3 = ع (ayn). Map before stripping digits so sami3naa ≈ samiAAna.
        s = s.replacingOccurrences(of: "3", with: "a")

        // Common digraph / Buckwalter cleanup before stripping punctuation.
        let replacements: [(String, String)] = [
            ("aa", "a"),
            ("ee", "i"),
            ("ii", "i"),
            ("oo", "u"),
            ("uu", "u"),
            ("quraan", "quran"),
            ("qur'an", "quran"),
            ("qur’an", "quran"),
            ("allaah", "allah"),
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // Tanzil uses AA for ع; collapse to a for matching.
        s = s.replacingOccurrences(of: "aa", with: "a")

        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(s.unicodeScalars.count)
        for scalar in s.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || scalar == " " {
                scalars.append(scalar)
            } else if scalar == "'" || scalar == "’" || scalar == "`" {
                continue
            } else {
                // Drop remaining digits / punctuation (verse-key queries are handled separately).
                scalars.append(" ")
            }
        }
        s = String(String.UnicodeScalarView(scalars))
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ normalized: String) -> [String] {
        normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private static func verseParts(_ key: String) -> (surah: Int, ayah: Int) {
        let parts = key.split(separator: ":")
        let surah = parts.first.flatMap { Int($0) } ?? 0
        let ayah = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (surah, ayah)
    }

    static func parseVerseKey(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\s*(\d{1,3})\s*[:\.\- ]\s*(\d{1,3})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges == 3,
              let surahRange = Range(match.range(at: 1), in: trimmed),
              let ayahRange = Range(match.range(at: 2), in: trimmed),
              let surah = Int(trimmed[surahRange]),
              let ayah = Int(trimmed[ayahRange]),
              (1...114).contains(surah),
              ayah >= 1
        else { return nil }
        return "\(surah):\(ayah)"
    }

    // MARK: - Index load

    private static func entries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedEntries { return cachedEntries }

        guard let url = Bundle.main.url(forResource: "phonetic-ayahs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(IndexFile.self, from: data)
        else {
            cachedEntries = []
            return []
        }

        let loaded: [Entry] = file.ayahs.map { row in
            let tokens = tokenize(normalize(row.t))
            return Entry(
                verseKey: row.k,
                transliteration: row.t,
                arabic: row.a,
                pageIndoPak: row.p2,
                pageUthmani: row.p3,
                normalized: tokens.joined(separator: " "),
                tokens: tokens
            )
        }
        cachedEntries = loaded
        return loaded
    }

    private static func hit(
        from entry: Entry,
        mushafID: Int,
        score: Double,
        matchWordRange: Range<Int>?
    ) -> PhoneticVerseHit {
        let page: Int?
        switch mushafID {
        case MushafID.uthmani.rawValue:
            page = entry.pageUthmani ?? entry.pageIndoPak
        default:
            page = entry.pageIndoPak ?? entry.pageUthmani
        }
        return PhoneticVerseHit(
            verseKey: entry.verseKey,
            transliteration: entry.transliteration,
            arabic: entry.arabic,
            page: page,
            score: score,
            matchWordRange: matchWordRange
        )
    }

    // MARK: - Highlighting

    struct SnippetWindow {
        let words: [String]
        /// Match range relative to `words`.
        let localMatchRange: Range<Int>?
        let leadingEllipsis: Bool
        let trailingEllipsis: Bool

        var display: String {
            let core = words.joined(separator: " ")
            return (leadingEllipsis ? "…" : "") + core + (trailingEllipsis ? "…" : "")
        }
    }

    static func snippetWindow(
        _ text: String,
        aroundWords range: Range<Int>?,
        maxChars: Int
    ) -> SnippetWindow {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return SnippetWindow(words: [], localMatchRange: nil, leadingEllipsis: false, trailingEllipsis: false)
        }

        if trimmed.count <= maxChars {
            let local = range.flatMap { clamp($0, to: words.count) }
            return SnippetWindow(words: words, localMatchRange: local, leadingEllipsis: false, trailingEllipsis: false)
        }

        guard let range, !range.isEmpty else {
            var taken: [String] = []
            var count = 0
            for word in words {
                let next = count + word.count + (taken.isEmpty ? 0 : 1)
                if next > maxChars - 1 { break }
                taken.append(word)
                count = next
            }
            return SnippetWindow(
                words: taken,
                localMatchRange: nil,
                leadingEllipsis: false,
                trailingEllipsis: taken.count < words.count
            )
        }

        let start = min(max(range.lowerBound, 0), words.count - 1)
        let end = min(max(range.upperBound, start + 1), words.count)
        var from = start
        var to = end
        var built = words[from..<to].joined(separator: " ")
        while built.count < maxChars - 8, from > 0 || to < words.count {
            if from > 0 {
                from -= 1
                built = words[from..<to].joined(separator: " ")
            }
            if built.count >= maxChars - 8 { break }
            if to < words.count {
                to += 1
                built = words[from..<to].joined(separator: " ")
            }
        }
        let window = Array(words[from..<to])
        let localLower = start - from
        let localUpper = end - from
        let local = clamp(localLower..<localUpper, to: window.count)
        return SnippetWindow(
            words: window,
            localMatchRange: local,
            leadingEllipsis: from > 0,
            trailingEllipsis: to < words.count
        )
    }

    private static func clamp(_ range: Range<Int>, to count: Int) -> Range<Int>? {
        let lower = min(max(range.lowerBound, 0), count)
        let upper = min(max(range.upperBound, lower), count)
        return lower < upper ? lower..<upper : nil
    }

    /// Highlighted full ayah text (Arabic or transliteration).
    static func highlightedText(
        _ text: String,
        matchWordRange: Range<Int>?,
        baseColor: Color,
        highlightColor: Color,
        font: Font
    ) -> AttributedString {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return highlightedWords(
            words,
            matchWordRange: matchWordRange.flatMap { clamp($0, to: words.count) },
            leadingEllipsis: false,
            trailingEllipsis: false,
            baseColor: baseColor,
            highlightColor: highlightColor,
            font: font
        )
    }

    /// Highlighted snippet centered on the match.
    static func highlightedSnippet(
        _ text: String,
        matchWordRange: Range<Int>?,
        maxChars: Int,
        baseColor: Color,
        highlightColor: Color,
        font: Font
    ) -> AttributedString {
        let window = snippetWindow(text, aroundWords: matchWordRange, maxChars: maxChars)
        return highlightedWords(
            window.words,
            matchWordRange: window.localMatchRange,
            leadingEllipsis: window.leadingEllipsis,
            trailingEllipsis: window.trailingEllipsis,
            baseColor: baseColor,
            highlightColor: highlightColor,
            font: font
        )
    }

    private static func highlightedWords(
        _ words: [String],
        matchWordRange: Range<Int>?,
        leadingEllipsis: Bool,
        trailingEllipsis: Bool,
        baseColor: Color,
        highlightColor: Color,
        font: Font
    ) -> AttributedString {
        guard !words.isEmpty else {
            var empty = AttributedString("")
            empty.foregroundColor = baseColor
            empty.font = font
            return empty
        }

        var result = AttributedString()
        if leadingEllipsis {
            var ellipsis = AttributedString("…")
            ellipsis.foregroundColor = baseColor
            ellipsis.font = font
            result.append(ellipsis)
        }

        for (index, word) in words.enumerated() {
            if index > 0 { result.append(AttributedString(" ")) }
            var piece = AttributedString(word)
            piece.font = font
            if let matchWordRange, matchWordRange.contains(index) {
                piece.foregroundColor = highlightColor
                piece.backgroundColor = highlightColor.opacity(0.18)
                piece.font = font.weight(.semibold)
            } else {
                piece.foregroundColor = baseColor
            }
            result.append(piece)
        }

        if trailingEllipsis {
            var ellipsis = AttributedString("…")
            ellipsis.foregroundColor = baseColor
            ellipsis.font = font
            result.append(ellipsis)
        }
        return result
    }
}
