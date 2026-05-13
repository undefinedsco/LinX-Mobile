import Foundation
import OSLog

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
            LinxDiagnostics.runtime.info("models auth expired retrying with token refresh")
            do {
                return try await fetchPreferredModelID(forceRefresh: true)
            } catch let refreshedError as LinxRuntimeRequestError where refreshedError.authExpired {
                LinxDiagnostics.runtime.error("models auth expired after token refresh")
                authProvider.expireSession(message: AppConstants.loginExpiredMessage)
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }
        } catch {
            LinxDiagnostics.runtime.error("models preferred fallback to default error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public) defaultModelID=\(AppConstants.defaultModelID, privacy: .public)")
            return AppConstants.defaultModelID
        }
    }

    private func fetchPreferredModelID(forceRefresh: Bool) async throws -> String {
        let startedAt = Date()
        let token: String
        do {
            token = try await authProvider.accessToken(forceRefresh: forceRefresh)
        } catch {
            LinxDiagnostics.runtime.error("models token failed forceRefresh=\(forceRefresh, privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw error
        }

        var request = URLRequest(url: LinxSharedContract.Runtime.endpoint(
            runtimeBaseURL: runtimeBaseURL,
            version: runtimeVersion,
            path: "models"
        ), timeoutInterval: AppConstants.runtimeRequestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        LinxDiagnostics.runtime.info("models request start forceRefresh=\(forceRefresh, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(request)
        } catch is CancellationError {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.runtime.info("models request cancelled durationMs=\(durationMs, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public)")
            throw CancellationError()
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.runtime.error("models transport failed durationMs=\(durationMs, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw LinxRuntimeRequestError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            let error = LinxRuntimeRequestError.http(status: status, responseBody: body, prefix: "Models request failed (\(status))")
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.runtime.error("models non2xx status=\(status, privacy: .public) bytes=\(data.count, privacy: .public) durationMs=\(durationMs, privacy: .public) authExpired=\(error.authExpired, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw error
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        LinxDiagnostics.runtime.info("models response status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) durationMs=\(durationMs, privacy: .public) forceRefresh=\(forceRefresh, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public)")

        do {
            let decoded = try JSONDecoder().decode(RuntimeModelListResponse.self, from: data)
            let modelID = try Self.pickPreferredModelID(from: decoded.data)
            LinxDiagnostics.runtime.info("models decode succeeded count=\(decoded.data.count, privacy: .public) selectedModelID=\(modelID, privacy: .public)")
            return modelID
        } catch {
            LinxDiagnostics.runtime.error("models decode failed bytes=\(data.count, privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    nonisolated static func pickPreferredModelID(from models: [RuntimeModelSummary]) throws -> String {
        LinxSharedContract.preferredModelID(from: models)
    }
}
