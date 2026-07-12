import Foundation

struct RevelationSearchRequest: Encodable {
    let verses: String
}

struct RevelationSearchResult: Decodable {
    let arabic: String?
    let number: String?
    let item: RevelationItem?
    let translation: RevelationTranslation?
}

struct RevelationItem: Decodable {
    let ref: String?
}

struct RevelationTranslation: Decodable {
    let english: String?
    let urdu: String?

    var preferredText: String? {
        let englishText = english?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let englishText, !englishText.isEmpty { return englishText }
        let urduText = urdu?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let urduText, !urduText.isEmpty { return urduText }
        return nil
    }
}

enum RevelationClient {
    private static let baseURL = URL(string: "https://natadarrab-api-7-4298623a0ae3.herokuapp.com")!
    private static let session = URLSession.shared
    private static let decoder = JSONDecoder()

    static func search(verseKey: String) async throws -> RevelationSearchResult? {
        let url = baseURL.appendingPathComponent("revelations/search.json")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RevelationSearchRequest(verses: verseKey))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let results = try decoder.decode([RevelationSearchResult].self, from: data)
        return results.first
    }
}

struct SelectedVerseDetail: Equatable, Hashable {
    let displayRef: String
    let verseKey: String
    var translation: String?
    var isLoadingTranslation = true
    var translationError: String?
}
