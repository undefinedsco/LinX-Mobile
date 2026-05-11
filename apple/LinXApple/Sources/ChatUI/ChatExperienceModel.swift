import ExyteChat
import Foundation

@MainActor
final class ChatExperienceModel: ObservableObject {
    @Published private(set) var threads: [LinxThreadSummary] = []
    @Published private(set) var messages: [LinxChatMessage] = []
    @Published private(set) var selectedThread: LinxThreadSummary?
    @Published private(set) var activeModelID = AppConstants.defaultModelID
    @Published private(set) var isBootstrapping = false
    @Published private(set) var isSending = false
    @Published var isShowingThreadSheet = false
    @Published var errorMessage: String?

    private let authController: AuthSessionController
    private let repository: PodChatRepository
    private let modelCatalogClient: LinxModelCatalogClient
    private let runtimeService: LinxOpenAIChatService

    private var bootstrapCompleted = false
    private var loadedMessageLimit = AppConstants.pageSize
    private var streamingTask: Task<Void, Never>?

    init(authController: AuthSessionController) {
        self.authController = authController
        let podClient = PodSPARQLClient(authController: authController)
        self.repository = PodChatRepository(client: podClient)
        self.modelCatalogClient = LinxModelCatalogClient(authController: authController)
        self.runtimeService = LinxOpenAIChatService(authController: authController)
    }

    var currentWebID: String? {
        authController.session?.webID
    }

    var exyteMessages: [Message] {
        ExyteMessageAdapter.makeMessages(from: messages, currentWebID: currentWebID)
    }

    var canRetryLastUserMessage: Bool {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else {
            return false
        }
        return lastAssistant.status == .failed || lastAssistant.status == .cancelled
    }

    func bootstrapIfNeeded() async {
        guard authController.isAuthenticated else { return }
        if bootstrapCompleted { return }

        isBootstrapping = true
        errorMessage = nil

        do {
            let webID = try authController.webID()
            activeModelID = try await modelCatalogClient.preferredModelID()
            try await repository.bootstrap(webID: webID, modelID: activeModelID)
            try await reloadThreads(selectFirstIfNeeded: true)
            bootstrapCompleted = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isBootstrapping = false
    }

    func resetForLogout() {
        streamingTask?.cancel()
        streamingTask = nil
        threads = []
        messages = []
        selectedThread = nil
        loadedMessageLimit = AppConstants.pageSize
        bootstrapCompleted = false
        isBootstrapping = false
        isSending = false
        errorMessage = nil
        activeModelID = AppConstants.defaultModelID
        isShowingThreadSheet = false
    }

    func newChat() {
        streamingTask?.cancel()
        selectedThread = nil
        messages = []
        loadedMessageLimit = AppConstants.pageSize
        isShowingThreadSheet = false
    }

    func selectThread(_ thread: LinxThreadSummary) {
        selectedThread = thread
        loadedMessageLimit = AppConstants.pageSize
        isShowingThreadSheet = false

        Task {
            await loadMessagesForCurrentThread()
        }
    }

    func enqueueSend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isSending == false else { return }

        streamingTask = Task {
            await executeSend(text: trimmed)
        }
    }

    func cancelStreaming() {
        streamingTask?.cancel()
    }

    func retryLastUserMessage() {
        guard
            let failedAssistant = messages.last(where: { $0.role == .assistant && ($0.status == .failed || $0.status == .cancelled) }),
            let failedIndex = messages.lastIndex(where: { $0.id == failedAssistant.id })
        else {
            return
        }

        let previousMessages = messages[..<failedIndex]
        guard let userMessage = previousMessages.last(where: { $0.role == .user }) else {
            return
        }

        enqueueSend(userMessage.content)
    }

    func loadMoreMessages() {
        guard selectedThread != nil else { return }
        loadedMessageLimit += AppConstants.pageSize
        Task {
            await loadMessagesForCurrentThread()
        }
    }

    func message(for id: String) -> LinxChatMessage? {
        messages.first(where: { $0.id == id })
    }

    private func executeSend(text: String) async {
        isSending = true
        errorMessage = nil

        do {
            let webID = try authController.webID()
            let thread = try await ensureThread(for: text, webID: webID)

            let userMessage = try await repository.appendUserMessage(webID: webID, threadID: thread.id, content: text)
            messages.append(userMessage)

            let assistantPlaceholder = try await repository.appendAssistantPlaceholder(webID: webID, threadID: thread.id)
            messages.append(assistantPlaceholder)

            let history = messages
                .filter { $0.threadID == thread.id && $0.id != assistantPlaceholder.id }
                .sorted { $0.createdAt < $1.createdAt }

            var lastPersistedContent = ""
            var lastPersistedAt = Date.distantPast

            let finalContent = try await runtimeService.streamReply(messages: history, modelID: activeModelID) { accumulated in
                await MainActor.run {
                    self.replaceMessage(
                        id: assistantPlaceholder.id,
                        content: accumulated,
                        status: .streaming,
                        updatedAt: Date()
                    )
                }

                let now = Date()
                if now.timeIntervalSince(lastPersistedAt) >= 0.2 {
                    try await self.repository.patchAssistantMessage(
                        webID: webID,
                        threadID: thread.id,
                        messageID: assistantPlaceholder.id,
                        content: accumulated,
                        status: .streaming,
                        createdAt: assistantPlaceholder.createdAt
                    )
                    lastPersistedContent = accumulated
                    lastPersistedAt = now
                }
            }

            if finalContent != lastPersistedContent || finalContent.isEmpty {
                try await repository.patchAssistantMessage(
                    webID: webID,
                    threadID: thread.id,
                    messageID: assistantPlaceholder.id,
                    content: finalContent,
                    status: .completed,
                    createdAt: assistantPlaceholder.createdAt
                )
            }

            replaceMessage(id: assistantPlaceholder.id, content: finalContent, status: .completed, updatedAt: Date())
            try await reloadThreads(selectFirstIfNeeded: false)
        } catch is CancellationError {
            await markStreamingMessageAs(.cancelled)
        } catch {
            errorMessage = error.localizedDescription
            await markStreamingMessageAs(.failed)
        }

        isSending = false
        streamingTask = nil
    }

    private func ensureThread(for firstMessage: String, webID: String) async throws -> LinxThreadSummary {
        if let selectedThread {
            return selectedThread
        }

        let title = makeThreadTitle(from: firstMessage)
        let createdThread = try await repository.createThread(webID: webID, title: title)
        selectedThread = createdThread
        messages = []
        threads.insert(createdThread, at: 0)
        return createdThread
    }

    private func loadMessagesForCurrentThread() async {
        guard let selectedThread else { return }

        do {
            let webID = try authController.webID()
            let loaded = try await repository.loadMessages(
                webID: webID,
                threadID: selectedThread.id,
                limit: loadedMessageLimit
            )
            messages = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadThreads(selectFirstIfNeeded: Bool) async throws {
        let webID = try authController.webID()
        let loaded = try await repository.listThreads(webID: webID)
        threads = loaded.sorted { $0.updatedAt > $1.updatedAt }

        if let selectedThread, let updated = threads.first(where: { $0.id == selectedThread.id }) {
            self.selectedThread = updated
            await loadMessagesForCurrentThread()
            return
        }

        if selectFirstIfNeeded, let first = threads.first {
            selectedThread = first
            await loadMessagesForCurrentThread()
        }
    }

    private func makeThreadTitle(from text: String) -> String {
        let title = String(text.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? AppConstants.defaultThreadTitle : title
    }

    private func replaceMessage(id: String, content: String, status: LinxMessageStatus, updatedAt: Date) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].status = status
        messages[index].updatedAt = updatedAt
    }

    private func markStreamingMessageAs(_ status: LinxMessageStatus) async {
        guard
            let selectedThread,
            let webID = currentWebID,
            let lastAssistant = messages.last(where: { $0.role == .assistant && $0.status == .streaming })
        else {
            return
        }

        replaceMessage(id: lastAssistant.id, content: lastAssistant.content, status: status, updatedAt: Date())

        do {
            try await repository.patchAssistantMessage(
                webID: webID,
                threadID: selectedThread.id,
                messageID: lastAssistant.id,
                content: lastAssistant.content,
                status: status,
                createdAt: lastAssistant.createdAt
            )
            try await reloadThreads(selectFirstIfNeeded: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
