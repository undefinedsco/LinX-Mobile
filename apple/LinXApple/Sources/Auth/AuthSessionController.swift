import AppAuth
import Foundation
import UIKit

@MainActor
final class AuthSessionController: ObservableObject {
    @Published private(set) var phase: LinxLaunchPhase = .launching
    @Published private(set) var session: AuthenticatedSessionSnapshot?
    @Published var lastErrorMessage: String?

    private let discoveryClient = OIDCDiscoveryClient()
    private let registrar = DynamicClientRegistrar()
    private let keychain = KeychainSessionStore()

    private var authState: OIDAuthState?
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

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

            let authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: authStateData)
            self.authState = authState
            session = AuthenticatedSessionSnapshot(webID: metadata.webID, clientID: metadata.clientID)
            phase = .authenticated
        } catch {
            keychain.clearSession()
            phase = .unauthenticated
            lastErrorMessage = error.localizedDescription
        }
    }

    func login() async {
        do {
            phase = .launching
            lastErrorMessage = nil

            let discovery = try await discoveryClient.discover()
            let configuration = discovery.serviceConfiguration
            let clientID = try await clientID(for: configuration)
            let presenter = try presenterViewController()
            let request = PKCECoordinator.makeAuthorizationRequest(configuration: configuration, clientID: clientID)

            var completedAuthState: OIDAuthState?
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.currentAuthorizationFlow = OIDAuthState.authState(
                    byPresenting: request,
                    presenting: presenter
                ) { authState, error in
                    self.currentAuthorizationFlow = nil

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let authState else {
                        continuation.resume(throwing: LinxAppError.authFailed("Authorization completed without tokens."))
                        return
                    }

                    completedAuthState = authState
                    continuation.resume()
                }
            }

            guard let authState = completedAuthState else {
                throw LinxAppError.authFailed("Authorization completed without auth state.")
            }

            guard let idToken = authState.lastTokenResponse?.idToken else {
                throw LinxAppError.invalidIDToken
            }

            let webID = try JWTUtilities.extractWebID(fromIDToken: idToken)
            self.authState = authState
            session = AuthenticatedSessionSnapshot(webID: webID, clientID: clientID)
            try persistCurrentState(webID: webID, clientID: clientID)
            phase = .authenticated
        } catch {
            authState = nil
            currentAuthorizationFlow = nil
            session = nil
            phase = .unauthenticated
            lastErrorMessage = error.localizedDescription
        }
    }

    func logout() {
        currentAuthorizationFlow?.cancel()
        currentAuthorizationFlow = nil
        authState = nil
        session = nil
        keychain.clearAll()
        phase = .unauthenticated
        lastErrorMessage = nil
    }

    func expireSession(message: String = AppConstants.loginExpiredMessage) {
        currentAuthorizationFlow?.cancel()
        currentAuthorizationFlow = nil
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

        if forceRefresh {
            authState.setNeedsTokenRefresh()
        }

        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error {
                    self.expireSession(message: error.localizedDescription)
                    continuation.resume(throwing: error)
                    return
                }

                guard let accessToken else {
                    continuation.resume(throwing: LinxAppError.authFailed("Token refresh returned no access token."))
                    return
                }

                do {
                    try self.persistCurrentState(webID: snapshot.webID, clientID: snapshot.clientID)
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                }

                continuation.resume(returning: accessToken)
            }
        }
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

        let clientID = try await registrar.registerClient(configuration: configuration)
        try keychain.saveRegisteredClientID(clientID)
        return clientID
    }

    private func presenterViewController() throws -> UIViewController {
        guard let presenter = UIApplication.linxTopViewController() else {
            throw LinxAppError.missingPresenter
        }
        return presenter
    }

    private func persistCurrentState(webID: String, clientID: String) throws {
        guard let authState else { return }
        let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
        try keychain.saveAuthState(data)
        try keychain.saveSessionMetadata(.init(webID: webID, clientID: clientID))
        try keychain.saveRegisteredClientID(clientID)
    }
}
