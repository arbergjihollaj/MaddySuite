//
//  AIError.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation

// =====================================================
// MARK: - AIError
// [TAG: V2_AI_ERROR]
// =====================================================

enum AIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case server(statusCode: Int, message: String)
    case decoding(String)
    case cloudNotConfigured
    case missingCloudAPIKey
    case backendUnavailable(String)
    case allBackendsUnavailable(local: String?, cloud: String?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "Invalid URL: \(raw)"
        case .invalidResponse:
            return "The AI server returned an invalid response."
        case .server(let statusCode, let message):
            if message.isEmpty {
                return "AI server error (\(statusCode))."
            }
            return "AI server error (\(statusCode)): \(message)"
        case .decoding(let detail):
            return "Could not parse AI response: \(detail)"
        case .cloudNotConfigured:
            return "Cloud is disabled or not fully configured."
        case .missingCloudAPIKey:
            return "No cloud API key found. Add it in Settings > AI."
        case .backendUnavailable(let message):
            return message
        case .allBackendsUnavailable(let local, let cloud):
            let localText = local?.isEmpty == false ? local! : "not available"
            let cloudText = cloud?.isEmpty == false ? cloud! : "not available"
            return "AI is offline. Local: \(localText). Cloud: \(cloudText)."
        case .cancelled:
            return "Request cancelled."
        }
    }

    static func mapTransport(_ error: Error) -> AIError {
        if error is CancellationError {
            return .cancelled
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .backendUnavailable("Request timed out.")
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost:
                return .backendUnavailable("No connection to AI endpoint.")
            default:
                return .backendUnavailable(nsError.localizedDescription)
            }
        }

        return .backendUnavailable(error.localizedDescription)
    }
}
