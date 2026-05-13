import ExyteChat
import Foundation
#if DEBUG
import OSLog
#endif

@MainActor
final class ChatExperienceModel: ObservableObject {
    private enum BootstrapState {
        case idle
        case running
        case succeeded
        case failed
    }

    @Published private(set) var threads: [LinxThreadSummary] = []
    @Published private(set) var messages: [LinxChatMessage] = []
    @Published private(set) var selectedThread: LinxThreadSummary?
    @Published private(set) var activeModelID = AppConstants.defaultModelID
    @Published private var bootstrapState: BootstrapState = .idle
    @Published private(set) var isSending = false
    @Published private(set) var isLoadingMessages = false
    @Published var isShowingThreadSheet = false
    @Published var errorMessage: String?

    private let authController: AuthSessionController
    private let repository: PodChatRepository
    private let modelCatalogClient: LinxModelCatalogClient
    private let runtimeService: LinxOpenAIChatService

    private var loadedMessageLimit = AppConstants.pageSize
    private var hasLoadedAllMessages = true
    private var activeMessageLoadID = UUID()
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

    var isBootstrapping: Bool {
        bootstrapState == .running
    }

    var needsBootstrap: Bool {
        bootstrapState == .idle
    }

    var canRetryBootstrap: Bool {
        bootstrapState == .failed && authController.isAuthenticated
    }

    var canLoadMoreMessages: Bool {
        selectedThread != nil && hasLoadedAllMessages == false && isLoadingMessages == false
    }

    var exyteMessages: [Message] {
        ExyteMessageAdapter.makeMessages(from: messages, currentWebID: currentWebID)
    }

    func bootstrapIfNeeded() async {
        guard authController.isAuthenticated else { return }
        guard bootstrapState == .idle else { return }

        await runBootstrap()
    }

    func retryBootstrap() async {
        guard authController.isAuthenticated, bootstrapState == .failed else { return }
        bootstrapState = .idle
        await bootstrapIfNeeded()
    }

    private func runBootstrap() async {
        bootstrapState = .running
        errorMessage = nil
#if DEBUG
        let startedAt = Date()
        LinxDiagnostics.threadsModel.debug("bootstrap start")
#endif

        do {
            let webID = try authController.webID()
#if DEBUG
            LinxDiagnostics.threadsModel.debug("bootstrap webID resolved webID=\(webID, privacy: .private)")
#endif
            activeModelID = try await modelCatalogClient.preferredModelID()
#if DEBUG
            LinxDiagnostics.threadsModel.debug("bootstrap model resolved modelID=\(self.activeModelID, privacy: .public)")
#endif
            try await repository.bootstrap(webID: webID, modelID: activeModelID)
#if DEBUG
            LinxDiagnostics.threadsModel.debug("bootstrap repository ready")
#endif
            try await reloadThreads(selectFirstIfNeeded: true)
            bootstrapState = .succeeded
#if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.threadsModel.debug("bootstrap succeeded threads=\(self.threads.count, privacy: .public) selected=\(self.selectedThread?.id ?? "none", privacy: .private) durationMs=\(durationMs, privacy: .public)")
#endif
        } catch is CancellationError {
            bootstrapState = .idle
#if DEBUG
            LinxDiagnostics.threadsModel.debug("bootstrap cancelled")
#endif
        } catch {
            errorMessage = error.localizedDescription
            bootstrapState = .failed
#if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.threadsModel.error("bootstrap failed error=\(error.localizedDescription, privacy: .private) durationMs=\(durationMs, privacy: .public)")
#endif
        }
    }

    func resetForLogout() {
        sendTask?.cancel()
        sendTask = nil
        invalidateMessageLoads()
        threads = []
        messages = []
        selectedThread = nil
        loadedMessageLimit = AppConstants.pageSize
        hasLoadedAllMessages = true
        isLoadingMessages = false
        bootstrapState = .idle
        isSending = false
        errorMessage = nil
        activeModelID = AppConstants.defaultModelID
        isShowingThreadSheet = false
    }

    func newChat() {
        sendTask?.cancel()
        invalidateMessageLoads()
        selectedThread = nil
        messages = []
        loadedMessageLimit = AppConstants.pageSize
        hasLoadedAllMessages = true
        isLoadingMessages = false
        isShowingThreadSheet = false
    }

    func selectThread(_ thread: LinxThreadSummary) {
        invalidateMessageLoads()
        selectedThread = thread
        messages = []
        loadedMessageLimit = AppConstants.pageSize
        hasLoadedAllMessages = false
        isLoadingMessages = false
        isShowingThreadSheet = false

        Task {
            await loadMessagesForCurrentThread()
        }
    }

    func enqueueSend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isSending == false, bootstrapState != .running else { return }

        sendTask = Task {
            await executeSend(text: trimmed)
        }
    }

    func cancelSend() {
        sendTask?.cancel()
    }

    func loadMoreMessages() {
        guard canLoadMoreMessages else { return }
        loadedMessageLimit += AppConstants.pageSize
        Task {
            await loadMessagesForCurrentThread()
        }
    }

    func message(for id: String) -> LinxChatMessage? {
        messages.first(where: { $0.id == id })
    }

    nonisolated static func makeCompletionMessages(
        history: [LinxChatMessage],
        userMessage: LinxChatMessage,
        threadID: String
    ) -> [LinxChatMessage] {
        (history + [userMessage])
            .filter { $0.threadID == threadID }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id < $1.id
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private func executeSend(text: String) async {
        isSending = true
        errorMessage = nil

        do {
            let webID = try authController.webID()
            let thread = try await ensureThread(for: text, webID: webID)
            let persistedHistory = try await repository.loadAllMessages(webID: webID, threadID: thread.id)

            let userMessage = try await repository.appendUserMessage(webID: webID, threadID: thread.id, content: text)
            messages.append(userMessage)

            let completionMessages = Self.makeCompletionMessages(
                history: persistedHistory,
                userMessage: userMessage,
                threadID: thread.id
            )

            let completion = try await runtimeService.createCompletionResult(messages: completionMessages, modelID: activeModelID)
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
        hasLoadedAllMessages = true
        isLoadingMessages = false
        invalidateMessageLoads()
        return createdThread
    }

    private func loadMessagesForCurrentThread() async {
        guard let selectedThread else { return }
        let threadID = selectedThread.id
        let requestedLimit = loadedMessageLimit
        let loadID = UUID()
        activeMessageLoadID = loadID
        isLoadingMessages = true

        do {
            let webID = try authController.webID()
            let loaded = try await repository.loadMessages(
                webID: webID,
                threadID: threadID,
                limit: requestedLimit
            )
            guard activeMessageLoadID == loadID, self.selectedThread?.id == threadID else { return }
            hasLoadedAllMessages = loaded.count < requestedLimit
            messages = mergedMessages(loaded, preserving: messages, threadID: threadID)
        } catch {
            guard activeMessageLoadID == loadID, self.selectedThread?.id == threadID else { return }
            errorMessage = error.localizedDescription
        }

        if activeMessageLoadID == loadID {
            isLoadingMessages = false
        }
    }

    private func reloadThreads(selectFirstIfNeeded: Bool, reloadMessages: Bool = true) async throws {
        let webID = try authController.webID()
#if DEBUG
        let startedAt = Date()
        LinxDiagnostics.threadsModel.debug("reloadThreads start selectFirst=\(selectFirstIfNeeded, privacy: .public) reloadMessages=\(reloadMessages, privacy: .public) previousCount=\(self.threads.count, privacy: .public) selected=\(self.selectedThread?.id ?? "none", privacy: .private) webID=\(webID, privacy: .private)")
#endif
        let loaded = try await repository.listThreads(webID: webID)
        threads = loaded.sorted { $0.updatedAt > $1.updatedAt }
#if DEBUG
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        LinxDiagnostics.threadsModel.debug("reloadThreads repository returned loaded=\(loaded.count, privacy: .public) sorted=\(self.threads.count, privacy: .public) durationMs=\(durationMs, privacy: .public)")
#endif

        if let selectedThread, let updated = threads.first(where: { $0.id == selectedThread.id }) {
            self.selectedThread = updated
#if DEBUG
            LinxDiagnostics.threadsModel.debug("reloadThreads updated selected threadID=\(updated.id, privacy: .private) reloadMessages=\(reloadMessages, privacy: .public)")
#endif
            if reloadMessages {
                await loadMessagesForCurrentThread()
            }
            return
        }

        if selectFirstIfNeeded, let first = threads.first {
            selectedThread = first
            hasLoadedAllMessages = false
#if DEBUG
            LinxDiagnostics.threadsModel.debug("reloadThreads selected first threadID=\(first.id, privacy: .private)")
#endif
            await loadMessagesForCurrentThread()
            return
        }

#if DEBUG
        LinxDiagnostics.threadsModel.debug("reloadThreads completed without selection threadCount=\(self.threads.count, privacy: .public) selectFirst=\(selectFirstIfNeeded, privacy: .public)")
#endif
    }

    private func invalidateMessageLoads() {
        activeMessageLoadID = UUID()
    }

    private func mergedMessages(
        _ loaded: [LinxChatMessage],
        preserving current: [LinxChatMessage],
        threadID: String
    ) -> [LinxChatMessage] {
        var seenIDs = Set(loaded.map(\.id))
        var merged = loaded

        for message in current where message.threadID == threadID && seenIDs.contains(message.id) == false {
            seenIDs.insert(message.id)
            merged.append(message)
        }

        return merged.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }

}
