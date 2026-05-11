import Foundation

@MainActor
struct PodBootstrapper {
    let client: PodSPARQLClient

    func bootstrap(webID: String, modelID: String) async throws {
        let baseURL = try PodStoragePaths.podBaseURL(forWebID: webID)
        let now = Date()

        try await ensureContainer(PodStoragePaths.dataContainer(baseURL: baseURL))
        try await ensureContainer(PodStoragePaths.chatRootContainer(baseURL: baseURL))
        try await ensureContainer(PodStoragePaths.chatContainer(baseURL: baseURL, chatID: AppConstants.defaultChatID))
        try await ensureContainer(PodStoragePaths.agentsContainer(baseURL: baseURL))

        let chatResource = PodStoragePaths.chatIndexResource(baseURL: baseURL, chatID: AppConstants.defaultChatID)
        if try await client.head(chatResource) == false {
            try await client.putResource(
                chatResource,
                turtle: PodSPARQLBuilder.chatResourceTurtle(
                    chatURI: PodStoragePaths.chatURI(baseURL: baseURL, chatID: AppConstants.defaultChatID),
                    createdAt: now
                )
            )
        }

        let agentResource = PodStoragePaths.agentResource(baseURL: baseURL, agentID: AppConstants.defaultAgentID)
        if try await client.head(agentResource) == false {
            try await client.putResource(
                agentResource,
                turtle: PodSPARQLBuilder.agentResourceTurtle(
                    agentURI: PodStoragePaths.agentURI(baseURL: baseURL, agentID: AppConstants.defaultAgentID),
                    modelID: modelID,
                    createdAt: now
                )
            )
        }
    }

    private func ensureContainer(_ url: URL) async throws {
        if try await client.head(url) == false {
            try await client.putContainer(url)
        }
    }
}
