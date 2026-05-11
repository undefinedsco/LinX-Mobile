import AppAuth
import XCTest
@testable import LinXApple

final class AuthAndPodTests: XCTestCase {
    func testExtractWebIDFromTokenPrefersWebIDClaim() throws {
        let token = makeJWT(payload: [
            "sub": "https://subject.example/profile/card#me",
            "webid": "https://pod.example/profile/card#me",
        ])

        XCTAssertEqual(try JWTUtilities.extractWebID(fromIDToken: token), "https://pod.example/profile/card#me")
    }

    func testExtractWebIDFallsBackToSubject() throws {
        let token = makeJWT(payload: [
            "sub": "https://subject.example/profile/card#me",
        ])

        XCTAssertEqual(try JWTUtilities.extractWebID(fromIDToken: token), "https://subject.example/profile/card#me")
    }

    func testPodBaseURLResolver() throws {
        let url = try PodStoragePaths.podBaseURL(forWebID: "https://alice.example/profile/card#me")
        XCTAssertEqual(url.absoluteString, "https://alice.example/")
    }

    func testPreferredModelSelection() throws {
        let models = [
            RuntimeModelSummary(id: "other-model"),
            RuntimeModelSummary(id: AppConstants.defaultModelID),
        ]
        XCTAssertEqual(try LinxModelCatalogClient.pickPreferredModelID(from: models), AppConstants.defaultModelID)
    }

    func testSPARQLEscapingKeepsTripleQuotesSafe() {
        let escaped = PodSPARQLBuilder.escapeLiteral("hello\n\"world\"")
        XCTAssertTrue(escaped.contains("\"\"\""))
        XCTAssertTrue(escaped.contains("world"))
    }

    func testPKCERequestUsesExpectedRedirectAndScopes() {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://id.undefineds.co/.oidc/auth")!,
            tokenEndpoint: URL(string: "https://id.undefineds.co/.oidc/token")!,
            issuer: AppConstants.issuerURL,
            registrationEndpoint: URL(string: "https://id.undefineds.co/.oidc/reg")!,
            endSessionEndpoint: nil
        )

        let request = PKCECoordinator.makeAuthorizationRequest(configuration: configuration, clientID: "client-id")

        XCTAssertEqual(request.clientID, "client-id")
        XCTAssertEqual(request.redirectURL, AppConstants.redirectURL)
        XCTAssertEqual(request.responseType, OIDResponseTypeCode)
        XCTAssertEqual(request.scope, AppConstants.loginScopes.joined(separator: " "))
        XCTAssertNotNil(request.codeChallenge)
        XCTAssertNotNil(request.codeVerifier)
    }

    private func makeJWT(payload: [String: String]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(encodeBase64URL(headerData)).\(encodeBase64URL(payloadData))."
    }

    private func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
