import Foundation

@MainActor
final class PodSPARQLClient {
    private let authController: AuthSessionController

    init(authController: AuthSessionController) {
        self.authController = authController
    }

    func head(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await authorizedData(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return false
        }

        return true
    }

    func putContainer(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("text/turtle", forHTTPHeaderField: "Content-Type")
        request.setValue("<http://www.w3.org/ns/ldp#BasicContainer>; rel=\"type\"", forHTTPHeaderField: "Link")
        request.httpBody = Data("<> a <http://www.w3.org/ns/ldp#BasicContainer> .".utf8)
        _ = try await expectSuccess(for: request)
    }

    func putResource(_ url: URL, turtle: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("text/turtle", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(turtle.utf8)
        _ = try await expectSuccess(for: request)
    }

    func patch(_ url: URL, sparql: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/sparql-update", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(sparql.utf8)
        _ = try await expectSuccess(for: request)
    }

    func query(endpoint: URL, sparql: String) async throws -> SPARQLQueryResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/sparql-query", forHTTPHeaderField: "Content-Type")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(sparql.utf8)

        let data = try await expectSuccess(for: request)
        return try JSONDecoder().decode(SPARQLQueryResponse.self, from: data)
    }

    private func expectSuccess(for request: URLRequest) async throws -> Data {
        let (data, response) = try await authorizedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let detail = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            if LinxRuntimeRequestError.http(status: httpResponse.statusCode, responseBody: detail).authExpired {
                authController.expireSession(message: AppConstants.loginExpiredMessage)
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }
            throw LinxAppError.podWriteFailed("Pod request failed (\(httpResponse.statusCode)): \(detail)")
        }

        return data
    }

    private func authorizedData(for request: URLRequest, retried: Bool = false) async throws -> (Data, URLResponse) {
        var authorizedRequest = request
        authorizedRequest.setValue("Bearer \(try await authController.accessToken(forceRefresh: retried))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authorizedRequest)

        if
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 401,
            retried == false
        {
            return try await authorizedData(for: request, retried: true)
        }

        return (data, response)
    }
}
