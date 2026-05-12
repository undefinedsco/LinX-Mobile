import Foundation

@MainActor
struct PodChatRepository {
    private let client: PodSPARQLClient
    private let bootstrapper: PodBootstrapper

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
        let response = try await queryChatEndpoints(
            baseURL: baseURL,
            sparql: PodSPARQLBuilder.threadsQuery(chatURI: chatURI, limit: limit)
        )

        return response.results.bindings.compactMap { binding in
            guard
                let threadValue = binding["thread"]?.value,
                let createdAt = LinxDate.parse(binding["createdAt"]?.value)
            else {
                return nil
            }

            let updatedAt = LinxDate.parse(binding["updatedAt"]?.value) ?? createdAt
            let title = binding["title"]?.value ?? AppConstants.defaultThreadTitle
            return LinxThreadSummary(
                id: PodStoragePaths.fragmentID(from: threadValue),
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    func loadMessages(
        webID: String,
        threadID: String,
        limit: Int,
        offset: Int = 0
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

        for endpoint in PodStoragePaths.chatSPARQLEndpoints(baseURL: baseURL, chatID: AppConstants.defaultChatID) {
            do {
                let response = try await client.query(endpoint: endpoint, sparql: sparql)
                if response.results.bindings.isEmpty == false {
                    return response
                }
                emptyResponse = emptyResponse ?? response
            } catch {
                lastError = error
            }
        }

        if let emptyResponse {
            return emptyResponse
        }

        throw lastError ?? LinxAppError.podWriteFailed("Pod query failed.")
    }
}
