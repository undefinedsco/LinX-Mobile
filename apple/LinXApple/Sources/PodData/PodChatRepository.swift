import Foundation
import OSLog

@MainActor
struct PodChatRepository {
    private let client: PodSPARQLClient
    private let bootstrapper: PodBootstrapper

    private struct ThreadMappingResult {
        let summaries: [LinxThreadSummary]
        let rawBindingCount: Int
        let missingThreadCount: Int
        let missingCreatedAtCount: Int
        let invalidCreatedAtCount: Int
        let createdAtFallbackCount: Int
        let emptyThreadIDCount: Int
    }

    init(client: PodSPARQLClient) {
        self.client = client
        self.bootstrapper = PodBootstrapper(client: client)
    }

    func bootstrap(webID: String, modelID: String) async throws {
        try await bootstrapper.bootstrap(webID: webID, modelID: modelID)
    }

    func listThreads(webID: String, limit: Int = AppConstants.pageSize) async throws -> [LinxThreadSummary] {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: webID)
        let chatURI = PodStoragePaths.chatURI(baseURL: baseURL, chatID: AppConstants.defaultChatID)
        LinxDiagnostics.podRepository.info("listThreads start limit=\(limit, privacy: .public) webIDHash=\(LinxDiagnostics.fingerprint(webID), privacy: .public) baseHost=\(baseURL.host ?? "-", privacy: .private) basePath=\(baseURL.path, privacy: .private) baseURLHash=\(LinxDiagnostics.fingerprint(url: baseURL), privacy: .public) chatURI=\(chatURI, privacy: .private) chatURIHash=\(LinxDiagnostics.fingerprint(chatURI), privacy: .public)")
        return try await queryThreadEndpoints(
            baseURL: baseURL,
            sparql: PodSPARQLBuilder.threadsQuery(chatURI: chatURI, limit: limit)
        )
    }

    private func mapThreadBindings(_ bindings: [[String: SPARQLValue]]) -> ThreadMappingResult {
        var summaries: [LinxThreadSummary] = []
        var missingThreadCount = 0
        var missingCreatedAtCount = 0
        var invalidCreatedAtCount = 0
        var createdAtFallbackCount = 0
        var emptyThreadIDCount = 0

        for binding in bindings {
            guard let threadValue = binding["thread"]?.value else {
                missingThreadCount += 1
                continue
            }

            let threadID = PodStoragePaths.fragmentID(from: threadValue)
            guard threadID.isEmpty == false else {
                emptyThreadIDCount += 1
                continue
            }

            let createdAtValue = binding["createdAt"]?.value
            let updatedAtValue = binding["updatedAt"]?.value
            let parsedCreatedAt = LinxDate.parse(createdAtValue)
            let parsedUpdatedAt = LinxDate.parse(updatedAtValue)

            if createdAtValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                missingCreatedAtCount += 1
            } else if parsedCreatedAt == nil {
                invalidCreatedAtCount += 1
                LinxDiagnostics.podRepository.debug("listThreads invalid createdAt type=\(binding["createdAt"]?.type ?? "-", privacy: .public) datatype=\(binding["createdAt"]?.datatype ?? "-", privacy: .public) updatedAtType=\(binding["updatedAt"]?.type ?? "-", privacy: .public) updatedAtDatatype=\(binding["updatedAt"]?.datatype ?? "-", privacy: .public)")
            }

            guard let createdAt = parsedCreatedAt ?? parsedUpdatedAt else {
                continue
            }

            if parsedCreatedAt == nil, parsedUpdatedAt != nil {
                createdAtFallbackCount += 1
            }

            let updatedAt = parsedUpdatedAt ?? createdAt
            let title = binding["title"]?.value ?? AppConstants.defaultThreadTitle
            summaries.append(LinxThreadSummary(
                id: threadID,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }

        return ThreadMappingResult(
            summaries: summaries,
            rawBindingCount: bindings.count,
            missingThreadCount: missingThreadCount,
            missingCreatedAtCount: missingCreatedAtCount,
            invalidCreatedAtCount: invalidCreatedAtCount,
            createdAtFallbackCount: createdAtFallbackCount,
            emptyThreadIDCount: emptyThreadIDCount
        )
    }

    private func queryThreadEndpoints(baseURL: URL, sparql: String) async throws -> [LinxThreadSummary] {
        var lastError: Error?
        var didReceiveResponse = false

        let endpoints = PodStoragePaths.chatSPARQLEndpoints(baseURL: baseURL, chatID: AppConstants.defaultChatID)
        for (index, endpoint) in endpoints.enumerated() {
            LinxDiagnostics.podRepository.info("queryChatEndpoints attempt index=\(index, privacy: .public) total=\(endpoints.count, privacy: .public) host=\(endpoint.host ?? "-", privacy: .private) path=\(endpoint.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: endpoint), privacy: .public) sparqlBytes=\(sparql.utf8.count, privacy: .public)")
            do {
                let response = try await client.query(endpoint: endpoint, sparql: sparql)
                didReceiveResponse = true
                let mapping = mapThreadBindings(response.results.bindings)
                LinxDiagnostics.podRepository.info("queryChatEndpoints response index=\(index, privacy: .public) bindings=\(mapping.rawBindingCount, privacy: .public) mapped=\(mapping.summaries.count, privacy: .public)")
                LinxDiagnostics.podRepository.debug("listThreads mapped rawBindings=\(mapping.rawBindingCount, privacy: .public) mapped=\(mapping.summaries.count, privacy: .public) missingThread=\(mapping.missingThreadCount, privacy: .public) missingCreatedAt=\(mapping.missingCreatedAtCount, privacy: .public) invalidCreatedAt=\(mapping.invalidCreatedAtCount, privacy: .public) createdAtFallback=\(mapping.createdAtFallbackCount, privacy: .public) emptyThreadID=\(mapping.emptyThreadIDCount, privacy: .public)")
                if mapping.summaries.isEmpty == false {
                    LinxDiagnostics.podRepository.info("queryChatEndpoints selected mapped index=\(index, privacy: .public) mapped=\(mapping.summaries.count, privacy: .public)")
                    return mapping.summaries
                }
            } catch {
                lastError = error
                LinxDiagnostics.podRepository.error("queryChatEndpoints endpoint error index=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            }
        }

        if didReceiveResponse {
            LinxDiagnostics.podRepository.info("queryChatEndpoints selected emptyMapped after all endpoints")
            return []
        }

        let resolvedError = lastError ?? LinxAppError.podWriteFailed("Pod query failed.")
        LinxDiagnostics.podRepository.error("queryChatEndpoints failed all endpoints error=\(resolvedError.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(resolvedError.localizedDescription), privacy: .public)")
        throw lastError ?? LinxAppError.podWriteFailed("Pod query failed.")
    }

    func loadMessages(
        webID: String,
        threadID: String,
        limit: Int,
        offset: Int = 0
    ) async throws -> [LinxChatMessage] {
        try await loadMessagesInternal(webID: webID, threadID: threadID, limit: limit, offset: offset)
    }

    func loadAllMessages(webID: String, threadID: String) async throws -> [LinxChatMessage] {
        try await loadMessagesInternal(webID: webID, threadID: threadID, limit: nil, offset: 0)
    }

    private func loadMessagesInternal(
        webID: String,
        threadID: String,
        limit: Int?,
        offset: Int
    ) async throws -> [LinxChatMessage] {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: webID)
        let threadURI = PodStoragePaths.threadURI(baseURL: baseURL, chatID: AppConstants.defaultChatID, threadID: threadID)
        let response = try await queryChatEndpoints(
            baseURL: baseURL,
            sparql: PodSPARQLBuilder.messagesQuery(threadURI: threadURI, limit: limit, offset: offset)
        )

        return response.results.bindings.compactMap { binding in
            guard
                let messageURI = binding["message"]?.value,
                let maker = binding["maker"]?.value,
                let roleValue = binding["role"]?.value,
                let role = LinxMessageRole(rawValue: roleValue),
                let content = binding["content"]?.value,
                let createdAt = LinxDate.parse(binding["createdAt"]?.value)
            else {
                return nil
            }

            let status = LinxMessageStatus(rawValue: binding["status"]?.value ?? "") ?? .sent
            return LinxChatMessage(
                id: PodStoragePaths.fragmentID(from: messageURI),
                threadID: threadID,
                maker: maker,
                role: role,
                content: content,
                richContent: binding["richContent"]?.value,
                status: status,
                createdAt: createdAt,
                updatedAt: LinxDate.parse(binding["updatedAt"]?.value)
            )
        }
        .reversed()
    }

    func createThread(
        webID: String,
        title: String = AppConstants.defaultThreadTitle,
        workspace: String = AppConstants.defaultThreadWorkspace
    ) async throws -> LinxThreadSummary {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: webID)
        let now = Date()
        let threadID = UUID().uuidString
        let indexURL = PodStoragePaths.chatIndexResource(baseURL: baseURL, chatID: AppConstants.defaultChatID)

        try await client.patch(
            indexURL,
            sparql: PodSPARQLBuilder.createThreadPatch(
                chatURI: PodStoragePaths.chatURI(baseURL: baseURL, chatID: AppConstants.defaultChatID),
                threadURI: PodStoragePaths.threadURI(baseURL: baseURL, chatID: AppConstants.defaultChatID, threadID: threadID),
                title: title,
                workspace: workspace,
                createdAt: now
            )
        )

        return LinxThreadSummary(id: threadID, title: title, createdAt: now, updatedAt: now)
    }

    func appendUserMessage(
        webID: String,
        threadID: String,
        content: String
    ) async throws -> LinxChatMessage {
        try await appendMessage(
            webID: webID,
            threadID: threadID,
            maker: webID,
            role: .user,
            content: content,
            status: .sent
        )
    }

    func appendAssistantMessage(
        webID: String,
        threadID: String,
        content: String
    ) async throws -> LinxChatMessage {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: webID)
        return try await appendMessage(
            webID: webID,
            threadID: threadID,
            maker: PodStoragePaths.agentURI(baseURL: baseURL, agentID: AppConstants.defaultAgentID),
            role: .assistant,
            content: content,
            status: .sent
        )
    }

    private func appendMessage(
        webID: String,
        threadID: String,
        maker: String,
        role: LinxMessageRole,
        content: String,
        status: LinxMessageStatus
    ) async throws -> LinxChatMessage {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: webID)
        let now = Date()
        let messageID = UUID().uuidString
        let resourceURL = PodStoragePaths.messageResource(baseURL: baseURL, chatID: AppConstants.defaultChatID, date: now)
        let messageURI = PodStoragePaths.messageSubjectURI(
            baseURL: baseURL,
            chatID: AppConstants.defaultChatID,
            messageID: messageID,
            date: now
        )
        let chatURI = PodStoragePaths.chatURI(baseURL: baseURL, chatID: AppConstants.defaultChatID)
        let threadURI = PodStoragePaths.threadURI(baseURL: baseURL, chatID: AppConstants.defaultChatID, threadID: threadID)

        try await ensureMessageDocument(baseURL: baseURL, date: now)
        try await client.patch(
            resourceURL,
            sparql: PodSPARQLBuilder.insertMessagePatch(
                chatURI: chatURI,
                threadURI: threadURI,
                messageURI: messageURI,
                makerURI: maker,
                role: role,
                content: content,
                status: status,
                createdAt: now
            )
        )
        try await patchActivity(baseURL: baseURL, threadID: threadID, preview: content, updatedAt: now)

        return LinxChatMessage(
            id: messageID,
            threadID: threadID,
            maker: maker,
            role: role,
            content: content,
            richContent: nil,
            status: status,
            createdAt: now,
            updatedAt: now
        )
    }

    private func ensureMessageDocument(baseURL: URL, date: Date) async throws {
        for container in PodStoragePaths.messageContainers(baseURL: baseURL, chatID: AppConstants.defaultChatID, date: date) {
            if try await client.head(container) == false {
                try await client.putContainer(container)
            }
        }

        let resourceURL = PodStoragePaths.messageResource(baseURL: baseURL, chatID: AppConstants.defaultChatID, date: date)
        if try await client.head(resourceURL) == false {
            try await client.putResource(resourceURL, turtle: PodSPARQLBuilder.ensureEmptyTurtleResource())
        }
    }

    private func patchActivity(baseURL: URL, threadID: String, preview: String, updatedAt: Date) async throws {
        try await client.patch(
            PodStoragePaths.chatIndexResource(baseURL: baseURL, chatID: AppConstants.defaultChatID),
            sparql: PodSPARQLBuilder.patchActivity(
                chatURI: PodStoragePaths.chatURI(baseURL: baseURL, chatID: AppConstants.defaultChatID),
                threadURI: PodStoragePaths.threadURI(baseURL: baseURL, chatID: AppConstants.defaultChatID, threadID: threadID),
                preview: String(preview.prefix(100)),
                updatedAt: updatedAt
            )
        )
    }

    private func queryChatEndpoints(baseURL: URL, sparql: String) async throws -> SPARQLQueryResponse {
        var emptyResponse: SPARQLQueryResponse?
        var lastError: Error?

        let endpoints = PodStoragePaths.chatSPARQLEndpoints(baseURL: baseURL, chatID: AppConstants.defaultChatID)
        for (index, endpoint) in endpoints.enumerated() {
            LinxDiagnostics.podRepository.info("queryChatEndpoints attempt index=\(index, privacy: .public) total=\(endpoints.count, privacy: .public) host=\(endpoint.host ?? "-", privacy: .private) path=\(endpoint.path, privacy: .private) urlHash=\(LinxDiagnostics.fingerprint(url: endpoint), privacy: .public) sparqlBytes=\(sparql.utf8.count, privacy: .public)")
            do {
                let response = try await client.query(endpoint: endpoint, sparql: sparql)
                let bindingCount = response.results.bindings.count
                LinxDiagnostics.podRepository.info("queryChatEndpoints response index=\(index, privacy: .public) bindings=\(bindingCount, privacy: .public)")
                if response.results.bindings.isEmpty == false {
                    LinxDiagnostics.podRepository.info("queryChatEndpoints selected nonEmpty index=\(index, privacy: .public) bindings=\(bindingCount, privacy: .public)")
                    return response
                }
                emptyResponse = emptyResponse ?? response
            } catch {
                lastError = error
                LinxDiagnostics.podRepository.error("queryChatEndpoints endpoint error index=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            }
        }

        if let emptyResponse {
            LinxDiagnostics.podRepository.info("queryChatEndpoints selected firstEmpty after all endpoints")
            return emptyResponse
        }

        let resolvedError = lastError ?? LinxAppError.podWriteFailed("Pod query failed.")
        LinxDiagnostics.podRepository.error("queryChatEndpoints failed all endpoints error=\(resolvedError.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(resolvedError.localizedDescription), privacy: .public)")
        throw lastError ?? LinxAppError.podWriteFailed("Pod query failed.")
    }
}
