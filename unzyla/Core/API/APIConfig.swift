import Foundation

enum APIConfig {
    static let railwayBase = "https://qiraat-api-v2-production.up.railway.app"

    static var baseURL: URL {
        URL(string: railwayBase)!
    }
}
