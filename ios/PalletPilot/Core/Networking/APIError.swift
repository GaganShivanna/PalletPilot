import Foundation

/// Structured errors for backend calls.
///
/// The backend returns `{"detail": "<message>"}` for 4xx failures (except 422,
/// which uses the standard FastAPI validation envelope). The detail string is
/// preserved but never parsed: there are no stable error codes (see
/// docs/ios/INTEGRATION_GAPS.md G14).
enum APIError: Error, Equatable {
    /// The request could not be built (bad path or parameters).
    case invalidRequest(String)
    /// Transport failure (offline, refused, timeout, ATS).
    case network(URLError)
    /// Non-2xx status. The detail message comes from the response body when present.
    case http(statusCode: Int, detail: String?)
    /// 2xx response whose body did not match the expected contract model.
    case decoding(Error)
    /// The response was not an HTTP response.
    case invalidResponse

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRequest(let a), .invalidRequest(let b)): return a == b
        case (.network(let a), .network(let b)): return a.code == b.code
        case (.http(let a, let b), .http(let c, let d)): return a == c && b == d
        case (.invalidResponse, .invalidResponse): return true
        case (.decoding, .decoding): return true
        default: return false
        }
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .network(let urlError):
            return urlError.localizedDescription
        case .http(let statusCode, let detail):
            if let detail, !detail.isEmpty { return detail }
            switch statusCode {
            case 404: return "Not found (404)."
            case 409: return "Conflict (409): already linked."
            case 413: return "Upload too large (413)."
            case 415: return "Unsupported file type (415)."
            case 422: return "The server rejected this request (422)."
            default: return "Server error (\(statusCode))."
            }
        case .decoding:
            return "Unexpected server response."
        case .invalidResponse:
            return "Invalid server response."
        }
    }
}

/// Envelope the backend uses for error bodies: `{"detail": "..."}`.
struct ErrorDetailResponse: Decodable {
    var detail: String?
}
