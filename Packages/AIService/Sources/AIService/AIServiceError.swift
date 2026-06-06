import Foundation

public enum AIServiceError: Error, Sendable {
    case missingAPIKey
    case networkError(underlying: Error)
    case httpError(statusCode: Int)
    case responseParsingFailed
    case streamingInterrupted(chunksReceived: Int, underlying: Error?)
}

extension AIServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "API key is not configured.")
        case .networkError:
            String(localized: "Network request failed. Please check your connection.")
        case let .httpError(statusCode):
            switch statusCode {
            case 401:
                String(localized: "Invalid API key. Please update your key in Settings.")
            case 429:
                String(localized: "Too many requests. Please try again later.")
            default:
                String(localized: "Server error (HTTP \(statusCode)). Please try again later.")
            }
        case .responseParsingFailed:
            String(localized: "Failed to parse AI response.")
        case .streamingInterrupted:
            String(localized: "Streaming connection was interrupted.")
        }
    }
}
