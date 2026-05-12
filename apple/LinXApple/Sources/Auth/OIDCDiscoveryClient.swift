import AppAuth
import Foundation

struct OIDCDiscoveryDocument: Decodable, Sendable {
    let issuer: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
    }

    var serviceConfiguration: OIDServiceConfiguration {
        OIDServiceConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            issuer: issuer,
            registrationEndpoint: registrationEndpoint,
            endSessionEndpoint: nil
        )
    }
}

struct OIDCDiscoveryClient {
    func discover() async throws -> OIDCDiscoveryDocument {
        var lastError: Error?

        for attempt in 1 ... 3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: AppConstants.discoveryURL)
                guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
                    throw LinxAppError.authFailed("OIDC discovery failed.")
                }

                return try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: data)
            } catch {
                lastError = error

                guard attempt < 3, Self.shouldRetry(error) else {
                    throw error
                }

                try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }

        throw lastError ?? LinxAppError.authFailed("OIDC discovery failed.")
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut:
            return true
        default:
            return false
        }
    }
}
