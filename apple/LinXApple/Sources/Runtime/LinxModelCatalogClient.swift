import Foundation

@MainActor
struct LinxModelCatalogClient {
    let authProvider: LinxRuntimeAuthProviding
    let transport: LinxHTTPTransport
    let runtimeBaseURL: URL
    let runtimeVersion: String

    init(
        authController: AuthSessionController,
        transport: LinxHTTPTransport = .shared,
        runtimeBaseURL: URL = AppConstants.runtimeBaseURL,
        runtimeVersion: String = AppConstants.runtimeVersion
    ) {
        self.authProvider = authController
        self.transport = transport
        self.runtimeBaseURL = runtimeBaseURL
        self.runtimeVersion = runtimeVersion
    }

    func preferredModelID() async throws -> String {
        do {
            return try await fetchPreferredModelID(forceRefresh: false)
        } catch let error as LinxRuntimeRequestError where error.authExpired {
            do {
                return try await fetchPreferredModelID(forceRefresh: true)
            } catch let refreshedError as LinxRuntimeRequestError where refreshedError.authExpired {
                authProvider.expireSession(message: AppConstants.loginExpiredMessage)
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }
        } catch {
            return AppConstants.defaultModelID
        }
    }

    private func fetchPreferredModelID(forceRefresh: Bool) async throws -> String {
        let token = try await authProvider.accessToken(forceRefresh: forceRefresh)
        var request = URLRequest(url: LinxSharedContract.Runtime.endpoint(
            runtimeBaseURL: runtimeBaseURL,
            version: runtimeVersion,
            path: "models"
        ))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.data(request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw LinxRuntimeRequestError.http(status: status, responseBody: body, prefix: "Models request failed (\(status))")
        }

        let decoded = try JSONDecoder().decode(RuntimeModelListResponse.self, from: data)
        return try Self.pickPreferredModelID(from: decoded.data)
    }

    nonisolated static func pickPreferredModelID(from models: [RuntimeModelSummary]) throws -> String {
        LinxSharedContract.preferredModelID(from: models)
    }
}
