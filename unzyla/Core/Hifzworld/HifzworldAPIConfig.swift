import Foundation

enum HifzworldAPIConfig {
    /// Update after deploying to Railway.
    static let baseURLString = "https://hifzworld-api-production.up.railway.app"

    static var baseURL: URL {
        URL(string: baseURLString)!
    }
}
