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
            "https://alice.example/.data/chat/ios-default/-/sparql",
        ])
    }

    func testLinxDateParseSupportsPodCompatibleFormats() throws {
        XCTAssertEqual(LinxDate.parse("1970-01-01T00:00:00.123Z")?.timeIntervalSince1970 ?? -1, 0.123, accuracy: 0.001)
        XCTAssertEqual(LinxDate.parse("1970-01-01T00:00:00Z")?.timeIntervalSince1970 ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(LinxDate.parse("1970-01-01 00:00:00 +0000")?.timeIntervalSince1970 ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(LinxDate.parse("1970-01-01")?.timeIntervalSince1970 ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(LinxDate.parse("1000000000")?.timeIntervalSince1970 ?? -1, 1_000_000_000, accuracy: 0.001)
        XCTAssertEqual(LinxDate.parse("1000000000000")?.timeIntervalSince1970 ?? -1, 1_000_000_000, accuracy: 0.001)
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
    func testRepositoryFallsBackToConcreteSPARQLEndpointWhenRootThreadBindingsDoNotMap() async throws {
        let endpointURLs = try chatEndpointURLs()
        let recorder = URLRequestLog()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .ok(threadSPARQLResponse(
                    id: "thread-bad-date",
                    title: "Bad Date Thread",
                    createdAt: "not-a-date",
                    updatedAt: nil
                )),
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
    func testRepositoryUsesUpdatedAtWhenCreatedAtIsInvalid() async throws {
        let endpointURLs = try chatEndpointURLs()
        let recorder = URLRequestLog()
        let repository = makeRepository(
            routes: [
                endpointURLs.root: .ok(threadSPARQLResponse(
                    id: "thread-4",
                    title: "Recovered Date Thread",
                    createdAt: "not-a-date",
                    updatedAt: "1970-01-01 00:01:00 +0000"
                )),
                endpointURLs.concrete: .ok(threadSPARQLResponse(id: "thread-5", title: "Unused Fallback Thread")),
            ],
            recorder: recorder
        )

        let threads = try await repository.listThreads(webID: testWebID)

        XCTAssertEqual(threads.map(\.id), ["thread-4"])
        XCTAssertEqual(threads.first?.createdAt.timeIntervalSince1970 ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(threads.first?.updatedAt.timeIntervalSince1970 ?? -1, 60, accuracy: 0.001)
        let requestedURLs = await recorder.urls
        XCTAssertEqual(requestedURLs.map(\.absoluteString), [endpointURLs.root])
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

    func testRuntimeResolverMapsCloudIssuerToRuntimeOrigin() throws {
        let runtimeOrigin = LinxRuntimeTargetResolver.resolveRuntimeOrigin(forIssuerURL: AppConstants.issuerURL)

        XCTAssertEqual(runtimeOrigin.absoluteString, "https://api.undefineds.co")
    }

    func testRuntimeResolverKeepsCustomIssuerAsRuntimeOrigin() throws {
        let runtimeOrigin = LinxRuntimeTargetResolver.resolveRuntimeOrigin(
            forIssuerURL: URL(string: "https://pods.example/runtime/")!
        )

        XCTAssertEqual(runtimeOrigin.absoluteString, "https://pods.example/runtime")
    }

    func testRuntimeResolverDoesNotDuplicateV1() throws {
        let apiBaseURL = LinxRuntimeTargetResolver.apiBaseURL(
            runtimeBaseURL: URL(string: "https://api.undefineds.co/v1/")!,
            version: AppConstants.runtimeVersion
        )

        XCTAssertEqual(apiBaseURL.absoluteString, "https://api.undefineds.co/v1")
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
        XCTAssertEqual(AppConstants.runtimeRequestTimeout, 600)
    }

    func testAllMessagesQueryOmitsPaginationLimit() {
        let query = PodSPARQLBuilder.messagesQuery(
            threadURI: "https://pod.example/.data/chat/ios-default/index.ttl#thread-1",
            limit: nil,
            offset: 0
        )

        XCTAssertFalse(query.contains("LIMIT"))
        XCTAssertFalse(query.contains("OFFSET"))
    }

    func testCompletionContextUsesFullPersistedHistoryPlusCurrentUserMessage() {
        let history = (0 ..< 25).map { index in
            makeMessage(
                id: "history-\(index)",
                threadID: "thread-1",
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "history \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let otherThreadMessage = makeMessage(
            id: "other-thread",
            threadID: "thread-2",
            role: .user,
            content: "ignore me",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let currentUserMessage = makeMessage(
            id: "current",
            threadID: "thread-1",
            role: .user,
            content: "current prompt",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let completionMessages = ChatExperienceModel.makeCompletionMessages(
            history: history + [otherThreadMessage],
            userMessage: currentUserMessage,
            threadID: "thread-1"
        )

        XCTAssertEqual(completionMessages.count, 26)
        XCTAssertEqual(completionMessages.first?.id, "history-0")
        XCTAssertEqual(completionMessages.last?.id, "current")
        XCTAssertFalse(completionMessages.contains(where: { $0.threadID == "thread-2" }))
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

    @MainActor
    func testPodClientHeadTreats404AsMissing() async throws {
        let transport = PodHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let client = PodSPARQLClient(
            authProvider: TestPodAuthProvider(),
            transport: transport
        )

        let exists = try await client.head(URL(string: "https://pod.example/.data/missing.ttl")!)

        XCTAssertFalse(exists)
    }

    @MainActor
    func testPodClientHeadRefreshesOnceOnUnauthorized() async throws {
        let statuses = HTTPStatusQueue([401, 204])
        let authProvider = RecordingPodAuthProvider()
        let transport = PodHTTPTransport { request in
            let status = await statuses.nextStatus()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("Unauthorized".utf8), response)
        }
        let client = PodSPARQLClient(authProvider: authProvider, transport: transport)

        let exists = try await client.head(URL(string: "https://pod.example/.data/chat/")!)

        XCTAssertTrue(exists)
        XCTAssertEqual(authProvider.forceRefreshCalls, [false, true])
        XCTAssertTrue(authProvider.expiredMessages.isEmpty)
    }

    @MainActor
    func testPodClientHeadExpiresSessionWhenUnauthorizedAfterRefresh() async throws {
        let statuses = HTTPStatusQueue([401, 401])
        let authProvider = RecordingPodAuthProvider()
        let transport = PodHTTPTransport { request in
            let status = await statuses.nextStatus()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("Unauthorized".utf8), response)
        }
        let client = PodSPARQLClient(authProvider: authProvider, transport: transport)

        do {
            _ = try await client.head(URL(string: "https://pod.example/.data/chat/")!)
            XCTFail("Expected expired session error")
        } catch let error as LinxAppError {
            XCTAssertEqual(error, .authFailed(AppConstants.loginExpiredMessage))
        }

        XCTAssertEqual(authProvider.forceRefreshCalls, [false, true])
        XCTAssertEqual(authProvider.expiredMessages, [AppConstants.loginExpiredMessage])
    }

    @MainActor
    func testPodClientHeadThrowsForServerFailure() async throws {
        let transport = PodHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("server down".utf8), response)
        }
        let client = PodSPARQLClient(authProvider: TestPodAuthProvider(), transport: transport)

        do {
            _ = try await client.head(URL(string: "https://pod.example/.data/chat/")!)
            XCTFail("Expected Pod HEAD failure")
        } catch let error as LinxAppError {
            guard case .podWriteFailed(let detail) = error else {
                XCTFail("Expected podWriteFailed, got \(error)")
                return
            }
            XCTAssertTrue(detail.contains("500"))
            XCTAssertTrue(detail.contains("server down"))
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

    func testThreadPatchPersistsIOSAlignedTitleAndWorkspace() {
        let patch = PodSPARQLBuilder.createThreadPatch(
            chatURI: "https://pod.example/.data/chat/ios-default/index.ttl#this",
            threadURI: "https://pod.example/.data/chat/ios-default/index.ttl#thread",
            title: AppConstants.defaultThreadTitle,
            workspace: AppConstants.defaultThreadWorkspace,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(patch.contains("iOS Session"))
        XCTAssertTrue(patch.contains("udfs:workspace <\(AppConstants.defaultThreadWorkspace)>"))
        XCTAssertEqual(AppConstants.defaultThreadWorkspace, "co.undefineds.linx.apple://workspace/default")
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
        XCTAssertEqual(request.additionalParameters?["prompt"], "consent")
    }

    @MainActor
    func testLoginRejectsAuthStateWithoutRefreshToken() async throws {
        let store = InMemoryAuthSessionStore()
        let authState = makeAuthState(refreshToken: nil)
        let controller = makeAuthController(keychain: store, authorizationAuthState: authState)

        await controller.login()

        XCTAssertEqual(controller.phase, .unauthenticated)
        XCTAssertNil(controller.session)
        XCTAssertEqual(controller.lastErrorMessage, AppConstants.loginExpiredMessage)
        XCTAssertNil(store.authStateData)
        XCTAssertNil(store.sessionMetadata)
        XCTAssertEqual(store.clearAllCount, 1)
    }

    @MainActor
    func testRestoreClearsPersistedAuthStateWithoutRefreshToken() async throws {
        let store = InMemoryAuthSessionStore()
        store.authStateData = try archivedAuthState(refreshToken: nil)
        store.sessionMetadata = .init(webID: testWebID, clientID: "client-id")
        let controller = makeAuthController(keychain: store)

        await controller.restore()

        XCTAssertEqual(controller.phase, .unauthenticated)
        XCTAssertNil(controller.session)
        XCTAssertEqual(controller.lastErrorMessage, AppConstants.loginExpiredMessage)
        XCTAssertNil(store.authStateData)
        XCTAssertNil(store.sessionMetadata)
        XCTAssertEqual(store.clearSessionCount, 1)
    }

    @MainActor
    func testRestoreAcceptsPersistedAuthStateWithRefreshToken() async throws {
        let store = InMemoryAuthSessionStore()
        store.authStateData = try archivedAuthState(refreshToken: "refresh-token")
        store.sessionMetadata = .init(webID: testWebID, clientID: "client-id")
        let controller = makeAuthController(keychain: store)

        await controller.restore()

        XCTAssertEqual(controller.phase, .authenticated)
        XCTAssertEqual(controller.session, .init(webID: testWebID, clientID: "client-id"))
        XCTAssertNil(controller.lastErrorMessage)
        XCTAssertEqual(store.clearSessionCount, 0)
    }

    func testMissingRefreshTokenErrorMapsToLoginExpiredMessage() {
        let sourceError = NSError(
            domain: "org.openid.appauth",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Unable to refresh expired token without a refresh token.",
            ]
        )

        let mapped = AuthSessionController.mapTokenRefreshError(sourceError)

        XCTAssertEqual(mapped as? LinxAppError, .authFailed(AppConstants.loginExpiredMessage))
    }

    private func makeJWT(payload: [String: String]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(encodeBase64URL(headerData)).\(encodeBase64URL(payloadData))."
    }

    private func makeMessage(
        id: String,
        threadID: String,
        role: LinxMessageRole,
        content: String,
        createdAt: Date
    ) -> LinxChatMessage {
        let maker = role == .assistant
            ? "https://alice.example/.data/agents/linx-cli-assistant.ttl"
            : testWebID

        return LinxChatMessage(
            id: id,
            threadID: threadID,
            maker: maker,
            role: role,
            content: content,
            richContent: nil,
            status: .sent,
            createdAt: createdAt,
            updatedAt: nil
        )
    }

    private func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeDiscoveryDocument() -> OIDCDiscoveryDocument {
        OIDCDiscoveryDocument(
            issuer: AppConstants.issuerURL,
            authorizationEndpoint: URL(string: "https://id.undefineds.co/.oidc/auth")!,
            tokenEndpoint: URL(string: "https://id.undefineds.co/.oidc/token")!,
            registrationEndpoint: URL(string: "https://id.undefineds.co/.oidc/reg")!
        )
    }

    @MainActor
    private func makeAuthController(
        keychain: InMemoryAuthSessionStore,
        authorizationAuthState: OIDAuthState? = nil
    ) -> AuthSessionController {
        let discovery = makeDiscoveryDocument()
        return AuthSessionController(
            discoverOIDC: { discovery },
            registerDynamicClient: { _ in "client-id" },
            keychain: keychain,
            presenterProvider: { UIViewController() },
            authorizationPresenter: { _, _ in
                guard let authorizationAuthState else {
                    throw LinxAppError.authFailed("Missing fake authorization state.")
                }
                return authorizationAuthState
            }
        )
    }

    private func makeAuthState(refreshToken: String?) -> OIDAuthState {
        let configuration = makeDiscoveryDocument().serviceConfiguration
        let tokenRequest = OIDTokenRequest(
            configuration: configuration,
            grantType: OIDGrantTypeAuthorizationCode,
            authorizationCode: "authorization-code",
            redirectURL: AppConstants.redirectURL,
            clientID: "client-id",
            clientSecret: nil,
            scopes: AppConstants.loginScopes,
            refreshToken: nil,
            codeVerifier: "code-verifier",
            additionalParameters: nil
        )
        var parameters: [String: NSObject & NSCopying] = [
            "access_token": "access-token" as NSString,
            "token_type": "Bearer" as NSString,
            "expires_in": NSNumber(value: 3600),
            "id_token": makeJWT(payload: ["webid": testWebID]) as NSString,
        ]
        if let refreshToken {
            parameters["refresh_token"] = refreshToken as NSString
        }
        let tokenResponse = OIDTokenResponse(request: tokenRequest, parameters: parameters)
        return OIDAuthState(authorizationResponse: nil, tokenResponse: tokenResponse, registrationResponse: nil)
    }

    private func archivedAuthState(refreshToken: String?) throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: makeAuthState(refreshToken: refreshToken),
            requiringSecureCoding: true
        )
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

    private func threadSPARQLResponse(
        id: String,
        title: String,
        createdAt: String? = "1970-01-01T00:00:00Z",
        updatedAt: String? = "1970-01-01T00:01:00Z"
    ) -> String {
        let createdAtField = createdAt.map {
            #""createdAt": { "type": "literal", "value": "\#($0)", "datatype": "http://www.w3.org/2001/XMLSchema#dateTime" }"#
        }
        let updatedAtField = updatedAt.map {
            #""updatedAt": { "type": "literal", "value": "\#($0)", "datatype": "http://www.w3.org/2001/XMLSchema#dateTime" }"#
        }
        let fields = [
            #""thread": { "type": "uri", "value": "https://alice.example/.data/chat/ios-default/index.ttl#\#(id)" }"#,
            #""title": { "type": "literal", "value": "\#(title)" }"#,
            createdAtField,
            updatedAtField,
        ].compactMap { $0 }.joined(separator: ",\n                ")

        return """
        {
          "results": {
            "bindings": [
              {
                \(fields)
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
                "message": { "type": "uri", "value": "https://alice.example/.data/chat/ios-default/1970/01/01/messages.ttl#\(id)" },
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

@MainActor
private final class InMemoryAuthSessionStore: AuthSessionStoring {
    var authStateData: Data?
    var sessionMetadata: StoredAuthSessionMetadata?
    var registeredClientID: String?
    private(set) var clearSessionCount = 0
    private(set) var clearAllCount = 0

    func saveAuthState(_ data: Data) throws {
        authStateData = data
    }

    func loadAuthState() throws -> Data? {
        authStateData
    }

    func saveSessionMetadata(_ metadata: StoredAuthSessionMetadata) throws {
        sessionMetadata = metadata
    }

    func loadSessionMetadata() throws -> StoredAuthSessionMetadata? {
        sessionMetadata
    }

    func saveRegisteredClientID(_ clientID: String) throws {
        registeredClientID = clientID
    }

    func loadRegisteredClientID() throws -> String? {
        registeredClientID
    }

    func clearSession() {
        clearSessionCount += 1
        authStateData = nil
        sessionMetadata = nil
    }

    func clearAll() {
        clearAllCount += 1
        authStateData = nil
        sessionMetadata = nil
        registeredClientID = nil
    }
}

private actor HTTPStatusQueue {
    private var statuses: [Int]

    init(_ statuses: [Int]) {
        self.statuses = statuses
    }

    func nextStatus() -> Int {
        if statuses.isEmpty {
            return 204
        }
        return statuses.removeFirst()
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

@MainActor
private final class RecordingPodAuthProvider: PodSPARQLAuthProviding {
    private(set) var forceRefreshCalls: [Bool] = []
    private(set) var expiredMessages: [String] = []

    func accessToken(forceRefresh: Bool) async throws -> String {
        forceRefreshCalls.append(forceRefresh)
        return forceRefresh ? "refreshed-token" : "test-token"
    }

    func expireSession(message: String) {
        expiredMessages.append(message)
    }
}
