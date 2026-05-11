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
        let (data, response) = try await URLSession.shared.data(from: AppConstants.discoveryURL)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw LinxAppError.authFailed("OIDC discovery failed.")
        }

        return try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: data)
    }
}
