import Foundation

enum HifzworldAPIConfig {
    /// Update after deploying to Railway.
    static let baseURLString = "https://hifzworld-api-production.up.railway.app"

    /// Numeric App Store Connect Apple ID (fallback if `/api/app_config` omits it).
    static let appStoreID = "6784750620"

    static var baseURL: URL {
        URL(string: baseURLString)!
    }
}
