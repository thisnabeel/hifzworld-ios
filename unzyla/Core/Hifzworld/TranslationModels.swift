import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case urdu = "ur"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .urdu: "Urdu"
        }
    }

    var isRightToLeft: Bool { self == .urdu }
}

struct VerseTranslationsResponse: Decodable {
    let translationSet: TranslationSetDTO
    let translations: [String: String]

    enum CodingKeys: String, CodingKey {
        case translationSet = "translation_set"
        case translations
    }
}

struct TranslationSetDTO: Decodable {
    let language: String
    let translator: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case language, translator
        case displayName = "display_name"
    }
}

enum TranslationDisplayText {
    /// Cosmetic: many `natadarrab` rows omit a final stop. Add one when missing.
    static func polished(_ text: String, language: TranslationLanguage = .english) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", "»", ")", "]", "}"]
        let terminals: Set<Character> = [".", "!", "?", "…", "\u{06D4}", "\u{061F}"]

        var significant = trimmed.endIndex
        var idx = trimmed.index(before: significant)
        while closers.contains(trimmed[idx]), idx > trimmed.startIndex {
            significant = idx
            idx = trimmed.index(before: idx)
        }

        if terminals.contains(trimmed[idx]) {
            return trimmed
        }

        let stop: Character = language == .urdu ? "\u{06D4}" : "."
        if significant == trimmed.endIndex {
            return trimmed + String(stop)
        }
        var result = trimmed
        result.insert(stop, at: significant)
        return result
    }
}
