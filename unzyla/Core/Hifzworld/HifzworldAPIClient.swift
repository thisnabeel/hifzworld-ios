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

    func get<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "GET", body: Optional<Data>.none, authorized: authorized)
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

    func delete(_ path: String, authorized: Bool = true) async throws {
        var request = URLRequest(url: HifzworldAPIConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = KeychainTokenStore.load() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        body: Data?,
        authorized: Bool
    ) async throws -> T {
        var request = URLRequest(url: HifzworldAPIConfig.baseURL.appendingPathComponent(path))
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
