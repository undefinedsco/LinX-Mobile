import AppAuth
import Foundation

enum PKCECoordinator {
    static func makeAuthorizationRequest(
        configuration: OIDServiceConfiguration,
        clientID: String
    ) -> OIDAuthorizationRequest {
        OIDAuthorizationRequest(
            configuration: configuration,
            clientId: clientID,
            scopes: AppConstants.loginScopes,
            redirectURL: AppConstants.redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: [
                "prompt": "consent",
            ]
        )
    }
}
