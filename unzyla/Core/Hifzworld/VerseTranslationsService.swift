import Foundation

struct VerseTranslationsService {
    private let api = HifzworldAPIClient.shared
    private let chunkSize = 80

    func fetch(keys: [String], language: TranslationLanguage = .english) async throws -> [String: String] {
        let unique = Array(Set(keys.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }

        var merged: [String: String] = [:]
        for chunk in stride(from: 0, to: unique.count, by: chunkSize) {
            let slice = unique[chunk..<min(chunk + chunkSize, unique.count)]
            let query = [
                URLQueryItem(name: "keys", value: slice.joined(separator: ",")),
                URLQueryItem(name: "language", value: language.rawValue),
                URLQueryItem(name: "translator", value: "natadarrab")
            ]
            let response: VerseTranslationsResponse = try await api.get(
                "/api/translations",
                query: query,
                authorized: false,
                timeout: 10
            )
            for (key, text) in response.translations where !text.isEmpty {
                merged[key] = text
            }
        }
        return merged
    }
}
