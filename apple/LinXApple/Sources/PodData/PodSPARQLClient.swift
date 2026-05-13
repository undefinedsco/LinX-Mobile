import Foundation
import OSLog

@MainActor
protocol PodSPARQLAuthProviding: AnyObject {
    func accessToken(forceRefresh: Bool) async throws -> String
    func expireSession(message: String)
}

extension AuthSessionController: PodSPARQLAuthProviding {}

struct PodHTTPTransport: Sendable {
    let data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = PodHTTPTransport { request in
        try await URLSession.shared.data(for: request)
    }
}

@MainActor
final class PodSPARQLClient {
    private let authProvider: PodSPARQLAuthProviding
    private let transport: PodHTTPTransport
    private let requestTimeout: TimeInterval

    convenience init(
        authController: AuthSessionController,
        transport: PodHTTPTransport = .shared,
        requestTimeout: TimeInterval = AppConstants.podRequestTimeout
    ) {
        self.init(authProvider: authController, transport: transport, requestTimeout: requestTimeout)
    }

    init(
        authProvider: PodSPARQLAuthProviding,
        transport: PodHTTPTransport = .shared,
        requestTimeout: TimeInterval = AppConstants.podRequestTimeout
    ) {
        self.authProvider = authProvider
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    func head(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "HEAD"

        let (data, response) = try await authorizedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            LinxDiagnostics.podNetwork.debug("HEAD nonHTTPResponse host=\(url.host ?? "-", privacy: .private) path=\(url.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: url), privacy: .public) treatingExists=true")
            return true
        }

        if 200 ..< 300 ~= httpResponse.statusCode {
            LinxDiagnostics.podNetwork.debug("HEAD exists=true status=\(httpResponse.statusCode, privacy: .public) host=\(url.host ?? "-", privacy: .private) path=\(url.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: url), privacy: .public)")
            return true
        }

        if httpResponse.statusCode == 404 {
            LinxDiagnostics.podNetwork.debug("HEAD exists=false status=404 host=\(url.host ?? "-", privacy: .private) path=\(url.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: url), privacy: .public)")
            return false
        }

        let detail = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
        if LinxRuntimeRequestError.http(status: httpResponse.statusCode, responseBody: detail).authExpired {
            LinxDiagnostics.podNetwork.error("HEAD auth expired status=\(httpResponse.statusCode, privacy: .public) host=\(url.host ?? "-", privacy: .private) path=\(url.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: url), privacy: .public)")
            authProvider.expireSession(message: AppConstants.loginExpiredMessage)
            throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
        }

        LinxDiagnostics.podNetwork.error("HEAD failed status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) host=\(url.host ?? "-", privacy: .private) path=\(url.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: url), privacy: .public)")
        throw LinxAppError.podWriteFailed("Pod HEAD request failed (\(httpResponse.statusCode)): \(detail)")
    }

    func putContainer(_ url: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "PUT"
        request.setValue("text/turtle", forHTTPHeaderField: "Content-Type")
        request.setValue("<http://www.w3.org/ns/ldp#BasicContainer>; rel=\"type\"", forHTTPHeaderField: "Link")
        request.httpBody = Data("<> a <http://www.w3.org/ns/ldp#BasicContainer> .".utf8)
        _ = try await expectSuccess(for: request)
    }

    func putResource(_ url: URL, turtle: String) async throws {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "PUT"
        request.setValue("text/turtle", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(turtle.utf8)
        _ = try await expectSuccess(for: request)
    }

    func patch(_ url: URL, sparql: String) async throws {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "PATCH"
        request.setValue("application/sparql-update", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(sparql.utf8)
        _ = try await expectSuccess(for: request)
    }

    func query(endpoint: URL, sparql: String) async throws -> SPARQLQueryResponse {
        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/sparql-query", forHTTPHeaderField: "Content-Type")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(sparql.utf8)

        let data = try await expectSuccess(for: request)
        do {
            let decoded = try JSONDecoder().decode(SPARQLQueryResponse.self, from: data)
            LinxDiagnostics.podNetwork.debug("SPARQL decode succeeded bindings=\(decoded.results.bindings.count, privacy: .public) bytes=\(data.count, privacy: .public) host=\(endpoint.host ?? "-", privacy: .private) path=\(endpoint.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: endpoint), privacy: .public)")
            return decoded
        } catch {
            LinxDiagnostics.podNetwork.error("SPARQL decode failed bytes=\(data.count, privacy: .public) host=\(endpoint.host ?? "-", privacy: .private) path=\(endpoint.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: endpoint), privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    private func expectSuccess(for request: URLRequest) async throws -> Data {
        let (data, response) = try await authorizedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            LinxDiagnostics.podNetwork.info("request success nonHTTPResponse method=\(request.httpMethod ?? "GET", privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public)")
            return data
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let detail = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            LinxDiagnostics.podNetwork.error("request non2xx method=\(request.httpMethod ?? "GET", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public)")
            if LinxRuntimeRequestError.http(status: httpResponse.statusCode, responseBody: detail).authExpired {
                LinxDiagnostics.podNetwork.error("request auth expired method=\(request.httpMethod ?? "GET", privacy: .public) status=\(httpResponse.statusCode, privacy: .public)")
                authProvider.expireSession(message: AppConstants.loginExpiredMessage)
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }
            throw LinxAppError.podWriteFailed("Pod request failed (\(httpResponse.statusCode)): \(detail)")
        }

        return data
    }

    private func authorizedData(for request: URLRequest, retried: Bool = false) async throws -> (Data, URLResponse) {
        let startedAt = Date()
        LinxDiagnostics.podNetwork.info("request start method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) retried=\(retried, privacy: .public)")
        var authorizedRequest = request
        do {
            let token = try await authProvider.accessToken(forceRefresh: retried)
            authorizedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            LinxDiagnostics.podNetwork.error("request token failed method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) forceRefresh=\(retried, privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw error
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(authorizedRequest)
        } catch is CancellationError {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.info("request cancelled method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) durationMs=\(durationMs, privacy: .public)")
            throw CancellationError()
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.error("request transport error method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) durationMs=\(durationMs, privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            throw Self.mapTransportError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.info("request response method=\(request.httpMethod ?? "GET", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) durationMs=\(durationMs, privacy: .public) retried=\(retried, privacy: .public)")
            if httpResponse.statusCode == 401, retried == false {
                LinxDiagnostics.podNetwork.info("request 401 retry with forceRefresh method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public)")
                return try await authorizedData(for: request, retried: true)
            }
        } else {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.info("request response nonHTTP method=\(request.httpMethod ?? "GET", privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .private) path=\(request.url?.path ?? "-", privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: request.url), privacy: .public) durationMs=\(durationMs, privacy: .public)")
        }

        return (data, response)
    }

    private nonisolated static func mapTransportError(_ error: Error) -> Error {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return LinxAppError.requestTimedOut("Pod request timed out. Check your connection and try again.")
        }

        return error
    }
}
