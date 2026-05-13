import Foundation
#if DEBUG
import OSLog
#endif

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
#if DEBUG
            LinxDiagnostics.podNetwork.debug("HEAD nonHTTPResponse host=\(url.host ?? "-", privacy: .public) path=\(url.path, privacy: .private) treatingExists=true")
#endif
            return true
        }

        if 200 ..< 300 ~= httpResponse.statusCode {
#if DEBUG
            LinxDiagnostics.podNetwork.debug("HEAD exists=true status=\(httpResponse.statusCode, privacy: .public) host=\(url.host ?? "-", privacy: .public) path=\(url.path, privacy: .private)")
#endif
            return true
        }

        if httpResponse.statusCode == 404 {
#if DEBUG
            LinxDiagnostics.podNetwork.debug("HEAD exists=false status=404 host=\(url.host ?? "-", privacy: .public) path=\(url.path, privacy: .private)")
#endif
            return false
        }

        let detail = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
        if LinxRuntimeRequestError.http(status: httpResponse.statusCode, responseBody: detail).authExpired {
#if DEBUG
            LinxDiagnostics.podNetwork.error("HEAD auth expired status=\(httpResponse.statusCode, privacy: .public) host=\(url.host ?? "-", privacy: .public) path=\(url.path, privacy: .private)")
#endif
            authProvider.expireSession(message: AppConstants.loginExpiredMessage)
            throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
        }

#if DEBUG
        LinxDiagnostics.podNetwork.error("HEAD failed status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) host=\(url.host ?? "-", privacy: .public) path=\(url.path, privacy: .private)")
#endif
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
#if DEBUG
            LinxDiagnostics.podNetwork.debug("SPARQL decode succeeded bindings=\(decoded.results.bindings.count, privacy: .public) bytes=\(data.count, privacy: .public) host=\(endpoint.host ?? "-", privacy: .public) path=\(endpoint.path, privacy: .private)")
#endif
            return decoded
        } catch {
#if DEBUG
            LinxDiagnostics.podNetwork.error("SPARQL decode failed bytes=\(data.count, privacy: .public) host=\(endpoint.host ?? "-", privacy: .public) path=\(endpoint.path, privacy: .private) error=\(error.localizedDescription, privacy: .private)")
#endif
            throw error
        }
    }

    private func expectSuccess(for request: URLRequest) async throws -> Data {
        let (data, response) = try await authorizedData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
#if DEBUG
            LinxDiagnostics.podNetwork.debug("request success nonHTTPResponse method=\(request.httpMethod ?? "GET", privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private)")
#endif
            return data
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let detail = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
#if DEBUG
            LinxDiagnostics.podNetwork.error("request non2xx method=\(request.httpMethod ?? "GET", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private)")
#endif
            if LinxRuntimeRequestError.http(status: httpResponse.statusCode, responseBody: detail).authExpired {
#if DEBUG
                LinxDiagnostics.podNetwork.error("request auth expired method=\(request.httpMethod ?? "GET", privacy: .public) status=\(httpResponse.statusCode, privacy: .public)")
#endif
                authProvider.expireSession(message: AppConstants.loginExpiredMessage)
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }
            throw LinxAppError.podWriteFailed("Pod request failed (\(httpResponse.statusCode)): \(detail)")
        }

        return data
    }

    private func authorizedData(for request: URLRequest, retried: Bool = false) async throws -> (Data, URLResponse) {
#if DEBUG
        let startedAt = Date()
        LinxDiagnostics.podNetwork.debug("request start method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private) retried=\(retried, privacy: .public)")
#endif
        var authorizedRequest = request
        do {
            let token = try await authProvider.accessToken(forceRefresh: retried)
            authorizedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
#if DEBUG
            LinxDiagnostics.podNetwork.error("request token failed method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private) forceRefresh=\(retried, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
#endif
            throw error
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(authorizedRequest)
        } catch is CancellationError {
#if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.debug("request cancelled method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private) durationMs=\(durationMs, privacy: .public)")
#endif
            throw CancellationError()
        } catch {
#if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.error("request transport error method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private) durationMs=\(durationMs, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
#endif
            throw Self.mapTransportError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
#if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.debug("request response method=\(request.httpMethod ?? "GET", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private) durationMs=\(durationMs, privacy: .public) retried=\(retried, privacy: .public)")
#endif
            if httpResponse.statusCode == 401, retried == false {
#if DEBUG
                LinxDiagnostics.podNetwork.debug("request 401 retry with forceRefresh method=\(request.httpMethod ?? "GET", privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private)")
#endif
                return try await authorizedData(for: request, retried: true)
            }
        } else {
#if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.podNetwork.debug("request response nonHTTP method=\(request.httpMethod ?? "GET", privacy: .public) bytes=\(data.count, privacy: .public) host=\(request.url?.host ?? "-", privacy: .public) path=\(request.url?.path ?? "-", privacy: .private) durationMs=\(durationMs, privacy: .public)")
#endif
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
