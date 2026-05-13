import AppAuth
import Foundation
import OSLog
import UIKit

@MainActor
protocol AuthSessionStoring: AnyObject {
    func saveAuthState(_ data: Data) throws
    func loadAuthState() throws -> Data?
    func saveSessionMetadata(_ metadata: StoredAuthSessionMetadata) throws
    func loadSessionMetadata() throws -> StoredAuthSessionMetadata?
    func saveRegisteredClientID(_ clientID: String) throws
    func loadRegisteredClientID() throws -> String?
    func clearSession()
    func clearAll()
}

extension KeychainSessionStore: AuthSessionStoring {}

@MainActor
final class AuthSessionController: ObservableObject {
    typealias DiscoveryHandler = @MainActor () async throws -> OIDCDiscoveryDocument
    typealias DynamicRegistrationHandler = @MainActor (OIDServiceConfiguration) async throws -> String
    typealias PresenterProvider = @MainActor () throws -> UIViewController
    typealias AuthorizationPresenter = @MainActor (OIDAuthorizationRequest, UIViewController) async throws -> OIDAuthState

    @Published private(set) var phase: LinxLaunchPhase = .launching
    @Published private(set) var session: AuthenticatedSessionSnapshot?
    @Published var lastErrorMessage: String?

    private let discoverOIDC: DiscoveryHandler
    private let registerDynamicClient: DynamicRegistrationHandler
    private let keychain: AuthSessionStoring
    private let presenterProvider: PresenterProvider
    private let authorizationPresenter: AuthorizationPresenter?

    private var authState: OIDAuthState?
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private var currentAuthorizationContinuation: CheckedContinuation<Void, Error>?
    private var completedAuthorizationState: OIDAuthState?

    init(
        discoverOIDC: @escaping DiscoveryHandler = { try await OIDCDiscoveryClient().discover() },
        registerDynamicClient: @escaping DynamicRegistrationHandler = { configuration in
            try await DynamicClientRegistrar().registerClient(configuration: configuration)
        },
        keychain: AuthSessionStoring = KeychainSessionStore(),
        presenterProvider: @escaping PresenterProvider = {
            guard let presenter = UIApplication.linxTopViewController() else {
                throw LinxAppError.missingPresenter
            }
            return presenter
        },
        authorizationPresenter: AuthorizationPresenter? = nil
    ) {
        self.discoverOIDC = discoverOIDC
        self.registerDynamicClient = registerDynamicClient
        self.keychain = keychain
        self.presenterProvider = presenterProvider
        self.authorizationPresenter = authorizationPresenter
    }

    var isAuthenticated: Bool {
        session != nil
    }

    func restore() async {
        do {
            guard
                let authStateData = try keychain.loadAuthState(),
                let metadata = try keychain.loadSessionMetadata()
            else {
                phase = .unauthenticated
                return
            }

            guard let authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: authStateData) else {
                keychain.clearSession()
                phase = .unauthenticated
                lastErrorMessage = AppConstants.loginExpiredMessage
                return
            }

            guard Self.hasUsableRefreshToken(authState) else {
                LinxDiagnostics.auth.error("restore rejected persisted auth state without refresh token webIDHash=\(LinxDiagnostics.fingerprint(metadata.webID), privacy: .public)")
                keychain.clearSession()
                self.authState = nil
                session = nil
                phase = .unauthenticated
                lastErrorMessage = AppConstants.loginExpiredMessage
                return
            }

            self.authState = authState
            session = AuthenticatedSessionSnapshot(webID: metadata.webID, clientID: metadata.clientID)
            phase = .authenticated
            LinxDiagnostics.auth.info("restore succeeded webIDHash=\(LinxDiagnostics.fingerprint(metadata.webID), privacy: .public)")
        } catch {
            LinxDiagnostics.auth.error("restore failed error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            keychain.clearSession()
            phase = .unauthenticated
            lastErrorMessage = error.localizedDescription
        }
    }

    func login() async {
        guard phase != .authenticating else { return }

        do {
            phase = .authenticating
            lastErrorMessage = nil

            let discovery = try await discoverOIDC()
            let configuration = discovery.serviceConfiguration
            let clientID = try await clientID(for: configuration)
            let presenter = try presenterProvider()
            let request = PKCECoordinator.makeAuthorizationRequest(configuration: configuration, clientID: clientID)

            let authState = try await authorize(request: request, presenter: presenter)

            guard Self.hasUsableRefreshToken(authState) else {
                LinxDiagnostics.auth.error("login rejected auth state without refresh token")
                keychain.clearAll()
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }

            guard let idToken = authState.lastTokenResponse?.idToken else {
                throw LinxAppError.invalidIDToken
            }

            let webID = try JWTUtilities.extractWebID(fromIDToken: idToken)
            self.authState = authState
            session = AuthenticatedSessionSnapshot(webID: webID, clientID: clientID)
            try persistCurrentState(webID: webID, clientID: clientID)
            phase = .authenticated
            LinxDiagnostics.auth.info("login succeeded webIDHash=\(LinxDiagnostics.fingerprint(webID), privacy: .public)")
        } catch {
            failLogin(with: error)
        }
    }

    func logout() {
        cancelAuthorizationFlow()
        authState = nil
        session = nil
        keychain.clearAll()
        phase = .unauthenticated
        lastErrorMessage = nil
    }

    func expireSession(message: String = AppConstants.loginExpiredMessage) {
        cancelAuthorizationFlow()
        authState = nil
        session = nil
        keychain.clearSession()
        phase = .unauthenticated
        lastErrorMessage = message
    }

    func handleRedirect(url: URL) {
        guard let currentAuthorizationFlow else { return }
        if currentAuthorizationFlow.resumeExternalUserAgentFlow(with: url) {
            self.currentAuthorizationFlow = nil
        }
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let authState, let snapshot = session else {
            throw LinxAppError.notAuthenticated
        }

        guard Self.hasUsableRefreshToken(authState) else {
            LinxDiagnostics.auth.error("access token request rejected auth state without refresh token webIDHash=\(LinxDiagnostics.fingerprint(snapshot.webID), privacy: .public)")
            let error = LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            expireSession(message: AppConstants.loginExpiredMessage)
            throw error
        }

        if forceRefresh {
            authState.setNeedsTokenRefresh()
        }

        return try await withCheckedThrowingContinuation { continuation in
            let continuationBox = ThrowingContinuationBox<String>(continuation)
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.timeoutNanoseconds(from: AppConstants.tokenRefreshTimeout))
                guard Task.isCancelled == false else { return }
                continuationBox.resume(throwing: LinxAppError.requestTimedOut("Refreshing your LinX Cloud session timed out. Check your connection and try again."))
            }

            authState.performAction { accessToken, _, error in
                Task { @MainActor in
                    timeoutTask.cancel()

                    if let error {
                        guard continuationBox.isPending else { return }
                        let mappedError = Self.mapTokenRefreshError(error)
                        LinxDiagnostics.auth.error("token refresh failed forceRefresh=\(forceRefresh, privacy: .public) webIDHash=\(LinxDiagnostics.fingerprint(snapshot.webID), privacy: .public) error=\(mappedError.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(mappedError.localizedDescription), privacy: .public)")
                        self.expireSession(message: mappedError.localizedDescription)
                        continuationBox.resume(throwing: mappedError)
                        return
                    }

                    guard let accessToken else {
                        let error = LinxAppError.authFailed("Token refresh returned no access token.")
                        LinxDiagnostics.auth.error("token refresh returned empty access token forceRefresh=\(forceRefresh, privacy: .public) webIDHash=\(LinxDiagnostics.fingerprint(snapshot.webID), privacy: .public)")
                        self.expireSession(message: error.localizedDescription)
                        continuationBox.resume(throwing: error)
                        return
                    }

                    guard continuationBox.isPending else { return }

                    do {
                        try self.persistCurrentState(webID: snapshot.webID, clientID: snapshot.clientID)
                    } catch {
                        self.lastErrorMessage = error.localizedDescription
                    }

                    continuationBox.resume(returning: accessToken)
                }
            }
        }
    }

    private nonisolated static func timeoutNanoseconds(from seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    nonisolated static func hasUsableRefreshToken(_ authState: OIDAuthState) -> Bool {
        guard let refreshToken = authState.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return refreshToken.isEmpty == false
    }

    nonisolated static func mapTokenRefreshError(_ error: Error) -> Error {
        if isMissingOrInvalidRefreshTokenError(error) {
            return LinxAppError.authFailed(AppConstants.loginExpiredMessage)
        }
        return error
    }

    private nonisolated static func isMissingOrInvalidRefreshTokenError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let values = [
            error.localizedDescription,
            nsError.domain,
            "\(nsError.code)",
        ]
        let normalized = values.joined(separator: " ").lowercased()

        return normalized.contains("without a refresh token")
            || normalized.contains("missing refresh")
            || normalized.contains("invalid refresh")
            || normalized.contains("invalid_grant")
            || normalized.contains("invalid_client")
            || normalized.contains("missing static client secret")
    }

    func webID() throws -> String {
        guard let webID = session?.webID else {
            throw LinxAppError.missingWebID
        }
        return webID
    }

    private func clientID(for configuration: OIDServiceConfiguration) async throws -> String {
        if let existing = try keychain.loadRegisteredClientID(), !existing.isEmpty {
            return existing
        }

        let clientID = try await registerDynamicClient(configuration)
        try keychain.saveRegisteredClientID(clientID)
        return clientID
    }

    private func authorize(
        request: OIDAuthorizationRequest,
        presenter: UIViewController
    ) async throws -> OIDAuthState {
        if let authorizationPresenter {
            return try await authorizationPresenter(request, presenter)
        }

        return try await presentAuthorization(request: request, presenter: presenter)
    }

    private func presentAuthorization(
        request: OIDAuthorizationRequest,
        presenter: UIViewController
    ) async throws -> OIDAuthState {
        completedAuthorizationState = nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            currentAuthorizationContinuation = continuation
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: presenter
            ) { authState, error in
                Task { @MainActor in
                    self.completeAuthorizationFlow(authState: authState, error: error)
                }
            }
        }

        guard let authState = completedAuthorizationState else {
            throw LinxAppError.authFailed("Authorization completed without auth state.")
        }

        completedAuthorizationState = nil
        return authState
    }

    private func completeAuthorizationFlow(authState: OIDAuthState?, error: Error?) {
        guard let continuation = currentAuthorizationContinuation else { return }

        currentAuthorizationContinuation = nil
        currentAuthorizationFlow = nil

        if let error {
            continuation.resume(throwing: error)
            return
        }

        guard let authState else {
            continuation.resume(throwing: LinxAppError.authFailed("Authorization completed without tokens."))
            return
        }

        completedAuthorizationState = authState
        continuation.resume()
    }

    private func cancelAuthorizationFlow() {
        currentAuthorizationFlow?.cancel()
        currentAuthorizationFlow = nil

        if let continuation = currentAuthorizationContinuation {
            currentAuthorizationContinuation = nil
            completedAuthorizationState = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    private func failLogin(with error: Error) {
        LinxDiagnostics.auth.error("login failed error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
        cancelAuthorizationFlow()
        authState = nil
        session = nil
        phase = .unauthenticated
        lastErrorMessage = error.localizedDescription
    }

    private func persistCurrentState(webID: String, clientID: String) throws {
        guard let authState else { return }
        let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
        try keychain.saveAuthState(data)
        try keychain.saveSessionMetadata(.init(webID: webID, clientID: clientID))
        try keychain.saveRegisteredClientID(clientID)
    }
}

@MainActor
private final class ThrowingContinuationBox<Success: Sendable> {
    private var continuation: CheckedContinuation<Success, Error>?

    init(_ continuation: CheckedContinuation<Success, Error>) {
        self.continuation = continuation
    }

    var isPending: Bool {
        continuation != nil
    }

    @discardableResult
    func resume(returning value: Success) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(throwing: error)
        return true
    }
}
