import AppAuth
import Foundation

@MainActor
struct DynamicClientRegistrar {
    func registerClient(configuration: OIDServiceConfiguration) async throws -> String {
        let request = OIDRegistrationRequest(
            configuration: configuration,
            redirectURIs: [AppConstants.redirectURL],
            responseTypes: [OIDResponseTypeCode],
            grantTypes: ["authorization_code", "refresh_token"],
            subjectType: nil,
            tokenEndpointAuthMethod: "none",
            additionalParameters: [
                "client_name": AppConstants.appName,
                "scope": AppConstants.loginScopes.joined(separator: " "),
            ]
        )

        return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(request) { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let response else {
                    continuation.resume(throwing: LinxAppError.authFailed("Client registration returned no response."))
                    return
                }

                continuation.resume(returning: response.clientID)
            }
        }
    }
}
