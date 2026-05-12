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
    private var sendTask: Task<Void, Never>?

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
        sendTask?.cancel()
        sendTask = nil
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
        sendTask?.cancel()
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

        sendTask = Task {
            await executeSend(text: trimmed)
        }
    }

    func cancelSend() {
        sendTask?.cancel()
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

            let history = messages
                .filter { $0.threadID == thread.id }
                .sorted { $0.createdAt < $1.createdAt }

            let completion = try await runtimeService.createCompletionResult(messages: history, modelID: activeModelID)
            let assistantMessage = try await repository.appendAssistantMessage(
                webID: webID,
                threadID: thread.id,
                content: completion.content
            )
            messages.append(assistantMessage)
            try await reloadThreads(selectFirstIfNeeded: false, reloadMessages: false)
        } catch is CancellationError {
            errorMessage = "LinX Cloud request aborted by user."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
        sendTask = nil
    }

    private func ensureThread(for _: String, webID: String) async throws -> LinxThreadSummary {
        if let selectedThread {
            return selectedThread
        }

        let createdThread = try await repository.createThread(
            webID: webID,
            title: AppConstants.defaultThreadTitle,
            workspace: AppConstants.defaultThreadWorkspace
        )
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

    private func reloadThreads(selectFirstIfNeeded: Bool, reloadMessages: Bool = true) async throws {
        let webID = try authController.webID()
        let loaded = try await repository.listThreads(webID: webID)
        threads = loaded.sorted { $0.updatedAt > $1.updatedAt }

        if let selectedThread, let updated = threads.first(where: { $0.id == selectedThread.id }) {
            self.selectedThread = updated
            if reloadMessages {
                await loadMessagesForCurrentThread()
            }
            return
        }

        if selectFirstIfNeeded, let first = threads.first {
            selectedThread = first
            await loadMessagesForCurrentThread()
        }
    }

}
