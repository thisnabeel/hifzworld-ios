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
            #if DEBUG
            return "Couldn't read server response (\(error.localizedDescription))"
            #else
            return "Couldn't read server response"
            #endif
        case .network(let error):
            return error.localizedDescription
        }
    }
}

extension APIError {
    /// Prefer API / decode messages over opaque system copy for auth UI.
    static func userFacingMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Something went wrong"
        }
        if error is DecodingError {
            return APIError.decoding(error).errorDescription ?? "Couldn't read server response"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return error.localizedDescription
        }
        return error.localizedDescription
    }
}
