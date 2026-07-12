import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case httpStatus(Int, message: String? = nil)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty { return message }
            return "HTTP error \(code)"
        case .decoding(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .network(let error):
            return error.localizedDescription
        }
    }
}
