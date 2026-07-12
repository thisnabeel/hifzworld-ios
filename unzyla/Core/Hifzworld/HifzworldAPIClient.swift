import Foundation

struct HifzworldAPIClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    static let shared = HifzworldAPIClient()

    func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        authorized: Bool = true
    ) async throws -> T {
        try await request(path: path, method: "GET", query: query, body: nil, authorized: authorized)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, authorized: Bool = true) async throws -> T {
        let data = try encoder.encode(body)
        return try await request(path: path, method: "POST", body: data, authorized: authorized)
    }

    func post<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "POST", body: Data(), authorized: authorized)
    }

    func patch<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "PATCH", body: Data(), authorized: authorized)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B, authorized: Bool = true) async throws -> T {
        let data = try encoder.encode(body)
        return try await request(path: path, method: "PATCH", body: data, authorized: authorized)
    }

    func delete(_ path: String, authorized: Bool = true) async throws {
        let _: EmptyResponse = try await request(path: path, method: "DELETE", body: nil, authorized: authorized)
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(string: HifzworldAPIConfig.baseURLString) else {
            throw APIError.invalidURL
        }
        let basePath = (components.path as NSString).appendingPathComponent(trimmed)
        components.path = basePath.hasPrefix("/") ? basePath : "/" + basePath
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data?,
        authorized: Bool
    ) async throws -> T {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authorized, let token = KeychainTokenStore.load() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.httpStatus(http.statusCode, message: apiError.error)
            }
            throw APIError.httpStatus(http.statusCode, message: nil)
        }
    }
}

private struct EmptyResponse: Decodable {}
