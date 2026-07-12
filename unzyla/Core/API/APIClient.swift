import Foundation

struct APIClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let url = try buildURL(path: path, query: query)
        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func getData(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let url = try buildURL(path: path, query: query)
        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        return data
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode(T.self, from: data)
    }

    func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        let url = try buildURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func buildURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }
}

extension APIClient {
    static let shared = APIClient()

    // MARK: - Global

    func fetchGlobalConfig() async throws -> GlobalConfigResponse {
        try await get("/api/global_config")
    }

    // MARK: - Narrators & variations

    func fetchNarrators() async throws -> [NarratorDTO] {
        try await get("/api/narrators")
    }

    func fetchVariations(wordIDs: [Int]) async throws -> [Variation] {
        guard !wordIDs.isEmpty else { return [] }
        let ids = wordIDs.map(String.init).joined(separator: ",")
        return try await get("/api/variations", query: [URLQueryItem(name: "word_ids", value: ids)])
    }

    func fetchVariations(mushafID: Int, narratorIDs: [String]) async throws -> [Variation] {
        let ids = narratorIDs.joined(separator: ",")
        return try await get(
            "/api/variations",
            query: [
                URLQueryItem(name: "mushaf_id", value: String(mushafID)),
                URLQueryItem(name: "narrator_ids", value: ids),
            ]
        )
    }

    func saveVariation(_ body: VariationSaveRequest) async throws -> Variation {
        try await post("/api/variations", body: body)
    }

    func deleteVariation(wordID: Int, narratorID: String) async throws {
        try await delete(
            "/api/variations/by_keys",
            query: [
                URLQueryItem(name: "word_id", value: String(wordID)),
                URLQueryItem(name: "narrator_id", value: narratorID),
            ]
        )
    }

    // MARK: - Mushaf

    func fetchMushaf(id: Int) async throws -> MushafInfo {
        try await get("/api/mushafs/\(id)")
    }

    func fetchPage(mushafID: Int, position: Int) async throws -> MushafPage {
        try await get("/api/mushafs/\(mushafID)/pages/\(position)")
    }

    func fetchSegments(mushafID: Int, category: String) async throws -> [MushafSegment] {
        try await get(
            "/api/mushafs/\(mushafID)/segments",
            query: [URLQueryItem(name: "category", value: category)]
        )
    }

    func fetchSurahHeaderMarkers(mushafID: Int) async throws -> SurahHeaderMarkersResponse {
        try await get("/api/mushafs/\(mushafID)/surah_header_markers")
    }

    func fetchWord(id: Int) async throws -> WordDetail {
        try await get("/api/words/\(id)")
    }

    // MARK: - Recitation

    func fetchReciters() async throws -> [Reciter] {
        try await get("/api/reciters")
    }

    func fetchRecitations(reciterSlug: String) async throws -> [Recitation] {
        try await get("/api/reciters/\(reciterSlug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reciterSlug)/recitations")
    }

    func fetchVerseSegments(recitationID: Int) async throws -> [VerseSegment] {
        try await get("/api/recitations/\(recitationID)/verse_segments")
    }

    func lookupVerseSegment(verse: String, narratorSlug: String) async throws -> VerseSegmentLookup {
        try await get(
            "/api/recitation_verse_segments/lookup",
            query: [
                URLQueryItem(name: "verse", value: verse),
                URLQueryItem(name: "narrator_slug", value: narratorSlug),
            ]
        )
    }
}
