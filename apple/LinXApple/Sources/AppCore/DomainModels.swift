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
