import Foundation

enum LinxLaunchPhase: Equatable {
    case launching
    case unauthenticated
    case authenticated
}

enum LinxMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

enum LinxMessageStatus: String, Codable, Sendable {
    case sent
    case streaming
    case completed
    case failed
    case cancelled
}

struct AuthenticatedSessionSnapshot: Equatable, Sendable {
    let webID: String
    let clientID: String
}

struct LinxThreadSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

struct LinxChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let threadID: String
    let maker: String
    let role: LinxMessageRole
    var content: String
    var richContent: String?
    var status: LinxMessageStatus
    let createdAt: Date
    var updatedAt: Date?
}

struct RuntimeModelSummary: Decodable, Equatable, Sendable {
    let id: String
    let provider: String?
    let ownedBy: String?
    let contextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case ownedBy = "owned_by"
        case contextWindow = "context_window"
    }

    init(id: String, provider: String? = nil, ownedBy: String? = nil, contextWindow: Int? = nil) {
        self.id = id
        self.provider = provider
        self.ownedBy = ownedBy
        self.contextWindow = contextWindow
    }
}

struct RuntimeModelListResponse: Decodable {
    let data: [RuntimeModelSummary]
}

enum LinxAppError: LocalizedError, Equatable {
    case notAuthenticated
    case missingWebID
    case missingPresenter
    case invalidIDToken
    case invalidRuntimeResponse
    case emptyModelCatalog
    case podWriteFailed(String)
    case runtimeFailed(String)
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Authentication is required."
        case .missingWebID:
            return "The identity provider did not return a WebID."
        case .missingPresenter:
            return "Unable to present the system authentication session."
        case .invalidIDToken:
            return "The ID token did not contain a valid WebID."
        case .invalidRuntimeResponse:
            return "The runtime returned an invalid response."
        case .emptyModelCatalog:
            return "No models are available for this account."
        case .podWriteFailed(let detail):
            return detail
        case .runtimeFailed(let detail):
            return detail
        case .authFailed(let detail):
            return detail
        }
    }
}

struct LinxRuntimeRequestError: LocalizedError, Equatable, Sendable {
    let message: String
    let status: Int
    let responseBody: String
    let authExpired: Bool

    var errorDescription: String? {
        message
    }

    static func http(status: Int, responseBody: String, prefix: String? = nil) -> LinxRuntimeRequestError {
        if isInvalidSolidTokenResponse(status: status, responseBody: responseBody) {
            return LinxRuntimeRequestError(
                message: AppConstants.loginExpiredMessage,
                status: status,
                responseBody: responseBody,
                authExpired: true
            )
        }

        if isTimeoutResponse(status: status, responseBody: responseBody) {
            return LinxRuntimeRequestError(
                message: "LinX Cloud request timed out upstream: \(extractRemoteErrorMessage(responseBody))",
                status: status,
                responseBody: responseBody,
                authExpired: false
            )
        }

        let resolvedPrefix = prefix ?? "Chat request failed (\(status))"
        return LinxRuntimeRequestError(
            message: "\(resolvedPrefix): \(responseBody)",
            status: status,
            responseBody: responseBody,
            authExpired: false
        )
    }

    static func transport(_ error: Error) -> LinxRuntimeRequestError {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return LinxRuntimeRequestError(
                message: "LinX Cloud request timed out.",
                status: 0,
                responseBody: urlError.localizedDescription,
                authExpired: false
            )
        }

        return LinxRuntimeRequestError(
            message: error.localizedDescription,
            status: 0,
            responseBody: error.localizedDescription,
            authExpired: false
        )
    }

    private static func isInvalidSolidTokenResponse(status: Int, responseBody: String) -> Bool {
        guard status == 401 else { return false }
        let normalized = responseBody.lowercased()
        return normalized.contains("invalid solid token") || normalized.contains("unauthorized")
    }

    private static func isTimeoutResponse(status: Int, responseBody: String) -> Bool {
        let normalized = responseBody.lowercased()
        return status >= 500 && normalized.contains("timeout") && normalized.contains("aborted")
    }

    private static func extractRemoteErrorMessage(_ responseBody: String) -> String {
        guard let data = responseBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(responseBody.prefix(300))
        }

        if let errorObject = json["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            return message
        }

        if let error = json["error"] as? String {
            return error
        }

        if let message = json["message"] as? String {
            return message
        }

        return String(responseBody.prefix(300))
    }
}
