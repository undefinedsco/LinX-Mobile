import AppAuth
import XCTest
@testable import LinXApple

final class AuthAndPodTests: XCTestCase {
    private let testWebID = "https://alice.example/profile/card#me"
    private let emptySPARQLResponse = #"{"results":{"bindings":[]}}"#

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

    func testChatSPARQLEndpointsPreferRootThenConcreteChatContainer() throws {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: "https://alice.example/profile/card#me")
        let endpoints = PodStoragePaths.chatSPARQLEndpoints(baseURL: baseURL, chatID: AppConstants.defaultChatID)

        XCTAssertEqual(endpoints.map(\.absoluteString), [
            "https://alice.example/.data/chat/-/sparql",
            "https://alice.example/.data/chat/cli-default/-/sparql",
        ])
    }

    @MainActor
    func testRepositoryListsThreadsFromRootSPARQLEndpoint() async throws {
        let endpointURLs = try chatEndpointURLs()
        let recorder = URLRequestLog()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .ok(threadSPARQLResponse(id: "thread-1", title: "Saved Thread")),
                endpointURLs.concrete: .ok(threadSPARQLResponse(id: "thread-2", title: "Fallback Thread")),
            ],
            recorder: recorder
        )

        let threads = try await repository.listThreads(webID: testWebID)

        XCTAssertEqual(threads.map(\.id), ["thread-1"])
        XCTAssertEqual(threads.first?.title, "Saved Thread")
        let requestedURLs = await recorder.urls
        XCTAssertEqual(requestedURLs.map(\.absoluteString), [endpointURLs.root])
    }

    @MainActor
    func testRepositoryFallsBackToConcreteSPARQLEndpointWhenRootIsEmpty() async throws {
        let endpointURLs = try chatEndpointURLs()
        let recorder = URLRequestLog()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .ok(emptySPARQLResponse),
                endpointURLs.concrete: .ok(threadSPARQLResponse(id: "thread-2", title: "Fallback Thread")),
            ],
            recorder: recorder
        )

        let threads = try await repository.listThreads(webID: testWebID)

        XCTAssertEqual(threads.map(\.id), ["thread-2"])
        let requestedURLs = await recorder.urls
        XCTAssertEqual(requestedURLs.map(\.absoluteString), [endpointURLs.root, endpointURLs.concrete])
    }

    @MainActor
    func testRepositoryReturnsEmptyWhenAllSPARQLEndpointsAreEmpty() async throws {
        let endpointURLs = try chatEndpointURLs()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .ok(emptySPARQLResponse),
                endpointURLs.concrete: .ok(emptySPARQLResponse),
            ]
        )

        let threads = try await repository.listThreads(webID: testWebID)

        XCTAssertTrue(threads.isEmpty)
    }

    @MainActor
    func testRepositoryIgnoresRootSPARQLFailureWhenFallbackSucceeds() async throws {
        let endpointURLs = try chatEndpointURLs()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .failure(status: 500),
                endpointURLs.concrete: .ok(threadSPARQLResponse(id: "thread-3", title: "Recovered Thread")),
            ]
        )

        let threads = try await repository.listThreads(webID: testWebID)

        XCTAssertEqual(threads.map(\.id), ["thread-3"])
    }

    @MainActor
    func testRepositoryLoadsMessagesFromFallbackSPARQLEndpoint() async throws {
        let endpointURLs = try chatEndpointURLs()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .ok(emptySPARQLResponse),
                endpointURLs.concrete: .ok(messageSPARQLResponse(id: "message-1", content: "hello again")),
            ]
        )

        let messages = try await repository.loadMessages(webID: testWebID, threadID: "thread-1", limit: 20)

        XCTAssertEqual(messages.map(\.id), ["message-1"])
        XCTAssertEqual(messages.first?.content, "hello again")
    }

    func testPreferredModelSelection() throws {
        let models = [
            RuntimeModelSummary(id: "other-model"),
            RuntimeModelSummary(id: AppConstants.defaultModelID),
        ]
        XCTAssertEqual(try LinxModelCatalogClient.pickPreferredModelID(from: models), AppConstants.defaultModelID)
    }

    func testPreferredModelSelectionFallsBackToDefaultWhenCatalogIsEmpty() throws {
        XCTAssertEqual(try LinxModelCatalogClient.pickPreferredModelID(from: []), AppConstants.defaultModelID)
    }

    func testRuntimeRequestBodyMatchesCLIChatCompletionContract() throws {
        let messages = [
            LinxChatMessage(
                id: "message-1",
                threadID: "thread-1",
                maker: "https://pod.example/profile/card#me",
                role: .user,
                content: "hello",
                richContent: nil,
                status: .sent,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: nil
            ),
        ]

        let body = LinxOpenAIChatService.makeRequestBody(messages: messages, modelID: AppConstants.defaultModelID)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, AppConstants.defaultModelID)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["tools"])
        XCTAssertNil(json["tool_choice"])

        let encodedMessages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(encodedMessages.count, 1)
        XCTAssertEqual(encodedMessages[0]["role"] as? String, "user")
        XCTAssertEqual(encodedMessages[0]["content"] as? String, "hello")
    }

    func testRuntimeRequestBodyIncludesToolsWhenProvided() throws {
        let tool = RemoteChatTool(
            type: "function",
            function: .init(
                name: "search",
                description: "Search documents",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("query")]),
                ])
            )
        )

        let body = LinxOpenAIChatService.makeRequestBody(
            messages: [],
            modelID: AppConstants.defaultModelID,
            tools: [tool]
        )
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["tool_choice"] as? String, "auto")
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["type"] as? String, "function")
    }

    func testRuntimeResponseDecodesReasoningToolCallsAndUsage() throws {
        let response = """
        {
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 5,
            "total_tokens": 99,
            "prompt_tokens_details": {
              "cached_tokens": 4,
              "cache_write_tokens": 1
            },
            "completion_tokens_details": {
              "reasoning_tokens": 2
            }
          },
          "choices": [
            {
              "finish_reason": "tool_calls",
              "message": {
                "content": [
                  { "type": "text", "text": "hello" }
                ],
                "reasoning_content": "thinking",
                "tool_calls": [
                  {
                    "id": "call-1",
                    "type": "function",
                    "function": {
                      "name": "search",
                      "arguments": "{\\"query\\":\\"hello\\"}"
                    }
                  }
                ]
              }
            }
          ]
        }
        """

        let result = try LinxOpenAIChatService.decodeCompletionResult(from: Data(response.utf8))

        XCTAssertEqual(result.content, "hello")
        XCTAssertEqual(result.reasoningContent, "thinking")
        XCTAssertEqual(result.finishReason, "tool_calls")
        XCTAssertEqual(result.toolCalls.first?.function.name, "search")
        XCTAssertEqual(result.usage, RemoteCompletionUsage(input: 6, output: 7, cacheRead: 3, cacheWrite: 1, totalTokens: 17))
    }

    func testRuntimeRequestURLDoesNotDuplicateV1() throws {
        let body = LinxOpenAIChatService.makeRequestBody(messages: [], modelID: AppConstants.defaultModelID)
        let request = try LinxOpenAIChatService.makeURLRequest(
            runtimeBaseURL: URL(string: "https://api.undefineds.co/v1/")!,
            runtimeVersion: AppConstants.runtimeVersion,
            apiKey: "token",
            body: body
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.undefineds.co/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.timeoutInterval, AppConstants.runtimeRequestTimeout)
    }

    @MainActor
    func testPodClientAppliesRequestTimeoutAndAuthorizationHeader() async throws {
        let recorder = RequestRecorder()
        let transport = PodHTTPTransport { request in
            await recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let client = PodSPARQLClient(
            authProvider: TestPodAuthProvider(),
            transport: transport,
            requestTimeout: 3
        )

        try await client.putResource(URL(string: "https://pod.example/.data/test.ttl")!, turtle: "<> a <urn:test> .")

        let recordedRequest = await recorder.request
        let capturedRequest = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(capturedRequest.timeoutInterval, 3)
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    @MainActor
    func testPodClientMapsTransportTimeout() async throws {
        let transport = PodHTTPTransport { _ in
            throw URLError(.timedOut)
        }
        let client = PodSPARQLClient(
            authProvider: TestPodAuthProvider(),
            transport: transport,
            requestTimeout: 1
        )

        do {
            _ = try await client.head(URL(string: "https://pod.example/.data/")!)
            XCTFail("Expected Pod timeout error")
        } catch let error as LinxAppError {
            XCTAssertEqual(
                error,
                .requestTimedOut("Pod request timed out. Check your connection and try again.")
            )
        }
    }

    func testRuntimeAuthExpiredErrorMatchesCLIInvalidSolidTokenMapping() {
        let error = LinxRuntimeRequestError.http(status: 401, responseBody: #"{"error":"invalid solid token"}"#)

        XCTAssertTrue(error.authExpired)
        XCTAssertEqual(error.message, AppConstants.loginExpiredMessage)
    }

    func testSharedContractUsesModelsWorkflowNamespace() {
        XCTAssertEqual(LinxSharedContract.Namespace.wf, "http://www.w3.org/2005/01/wf/flow-1.0#")
    }

    func testSharedContractMirrorsChatSubjectTemplates() {
        XCTAssertEqual(LinxSharedContract.Resource.SubjectTemplate.chat, "{id}/index.ttl#this")
        XCTAssertEqual(LinxSharedContract.Resource.SubjectTemplate.thread, "{chat|id}/index.ttl#{id}")
        XCTAssertEqual(LinxSharedContract.Resource.SubjectTemplate.message, "{chat|id}/{yyyy}/{MM}/{dd}/messages.ttl#{id}")
    }

    func testSPARQLEscapingKeepsTripleQuotesSafe() {
        let escaped = PodSPARQLBuilder.escapeLiteral("hello\n\"world\"")
        XCTAssertTrue(escaped.contains("\"\"\""))
        XCTAssertTrue(escaped.contains("world"))
    }

    func testThreadPatchPersistsCLIAlignedTitleAndWorkspace() {
        let patch = PodSPARQLBuilder.createThreadPatch(
            chatURI: "https://pod.example/.data/chat/cli-default/index.ttl#this",
            threadURI: "https://pod.example/.data/chat/cli-default/index.ttl#thread",
            title: AppConstants.defaultThreadTitle,
            workspace: AppConstants.defaultThreadWorkspace,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(patch.contains("CLI Session"))
        XCTAssertTrue(patch.contains("udfs:workspace <\(AppConstants.defaultThreadWorkspace)>"))
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

    private func chatEndpointURLs() throws -> (root: String, concrete: String) {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: testWebID)
        let endpoints = PodStoragePaths.chatSPARQLEndpoints(baseURL: baseURL, chatID: AppConstants.defaultChatID)
        return (endpoints[0].absoluteString, endpoints[1].absoluteString)
    }

    @MainActor
    private func makeRepository(
        routes: [String: MockHTTPRoute],
        recorder: URLRequestLog = URLRequestLog()
    ) -> PodChatRepository {
        let transport = PodHTTPTransport { request in
            await recorder.record(request)
            let route = routes[request.url?.absoluteString ?? ""] ?? .failure(status: 404)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: route.status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(route.body.utf8), response)
        }
        return PodChatRepository(client: PodSPARQLClient(authProvider: TestPodAuthProvider(), transport: transport))
    }

    private func threadSPARQLResponse(id: String, title: String) -> String {
        """
        {
          "results": {
            "bindings": [
              {
                "thread": { "type": "uri", "value": "https://alice.example/.data/chat/cli-default/index.ttl#\(id)" },
                "title": { "type": "literal", "value": "\(title)" },
                "createdAt": { "type": "literal", "value": "1970-01-01T00:00:00Z" },
                "updatedAt": { "type": "literal", "value": "1970-01-01T00:01:00Z" }
              }
            ]
          }
        }
        """
    }

    private func messageSPARQLResponse(id: String, content: String) -> String {
        """
        {
          "results": {
            "bindings": [
              {
                "message": { "type": "uri", "value": "https://alice.example/.data/chat/cli-default/1970/01/01/messages.ttl#\(id)" },
                "maker": { "type": "uri", "value": "https://alice.example/profile/card#me" },
                "role": { "type": "literal", "value": "user" },
                "content": { "type": "literal", "value": "\(content)" },
                "createdAt": { "type": "literal", "value": "1970-01-01T00:00:00Z" }
              }
            ]
          }
        }
        """
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

private actor URLRequestLog {
    private(set) var urls: [URL] = []

    func record(_ request: URLRequest) {
        if let url = request.url {
            urls.append(url)
        }
    }
}

private struct MockHTTPRoute: Sendable {
    let status: Int
    let body: String

    static func ok(_ body: String) -> MockHTTPRoute {
        MockHTTPRoute(status: 200, body: body)
    }

    static func failure(status: Int) -> MockHTTPRoute {
        MockHTTPRoute(status: status, body: "mock failure")
    }
}

@MainActor
private final class TestPodAuthProvider: PodSPARQLAuthProviding {
    func accessToken(forceRefresh _: Bool) async throws -> String {
        "test-token"
    }

    func expireSession(message _: String) {}
}
