import ExyteChat
import Foundation
import OSLog

@MainActor
protocol ChatRepositoryProviding: Sendable {
    func bootstrap(webID: String, modelID: String, force: Bool) async throws
    func listThreads(webID: String, limit: Int) async throws -> [LinxThreadSummary]
    func loadMessages(webID: String, threadID: String, limit: Int, offset: Int) async throws -> [LinxChatMessage]
    func loadAllMessages(webID: String, threadID: String) async throws -> [LinxChatMessage]
    func createThread(webID: String, title: String, workspace: String) async throws -> LinxThreadSummary
    func appendUserMessage(webID: String, threadID: String, content: String) async throws -> LinxChatMessage
    func appendAssistantMessage(webID: String, threadID: String, content: String) async throws -> LinxChatMessage
}

extension PodChatRepository: ChatRepositoryProviding, @unchecked Sendable {}

@MainActor
protocol ChatModelCatalogProviding: Sendable {
    func preferredModelID() async throws -> String
}

extension LinxModelCatalogClient: ChatModelCatalogProviding, @unchecked Sendable {}

@MainActor
protocol ChatCompletionProviding: Sendable {
    func createCompletionResult(
        messages: [LinxChatMessage],
        modelID: String,
        tools: [RemoteChatTool]
    ) async throws -> RemoteCompletionResult
}

extension LinxOpenAIChatService: ChatCompletionProviding, @unchecked Sendable {}

@MainActor
final class ChatExperienceModel: ObservableObject {
    private enum BootstrapState {
        case idle
        case running
        case succeeded
        case degraded
        case failed
    }

    private enum SyncDegradation {
        case emptyRemoteThreads
        case emptyRemoteMessages

        var message: String {
            switch self {
            case .emptyRemoteThreads:
                return "Pod returned no chat history. Showing cached chat data."
            case .emptyRemoteMessages:
                return "Pod returned no messages for this thread. Showing cached messages."
            }
        }
    }

    private struct ThreadReloadResult {
        let degradation: SyncDegradation?

        static let synced = ThreadReloadResult(degradation: nil)
    }

    private enum MessageLoadResult {
        case loaded
        case preservedCache(SyncDegradation)
        case failed(Error)
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
    private let repository: any ChatRepositoryProviding
    private let localCache: ChatLocalCacheStore
    private let modelCatalogClient: any ChatModelCatalogProviding
    private let runtimeService: any ChatCompletionProviding

    private var loadedMessageLimit = AppConstants.pageSize
    private var hasLoadedAllMessages = true
    private var activeMessageLoadID = UUID()
    private var cachedLaunchThreadID: String?
    private var sendTask: Task<Void, Never>?

    init(authController: AuthSessionController, localCache: ChatLocalCacheStore = ChatLocalCacheStore()) {
        self.authController = authController
        self.localCache = localCache
        let podClient = PodSPARQLClient(authController: authController)
        self.repository = PodChatRepository(client: podClient)
        self.modelCatalogClient = LinxModelCatalogClient(authController: authController)
        self.runtimeService = LinxOpenAIChatService(authController: authController)
    }

    init(
        authController: AuthSessionController,
        repository: any ChatRepositoryProviding,
        localCache: ChatLocalCacheStore = ChatLocalCacheStore(),
        modelCatalogClient: any ChatModelCatalogProviding,
        runtimeService: any ChatCompletionProviding
    ) {
        self.authController = authController
        self.repository = repository
        self.localCache = localCache
        self.modelCatalogClient = modelCatalogClient
        self.runtimeService = runtimeService
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
        (bootstrapState == .failed || bootstrapState == .degraded) && authController.isAuthenticated
    }

    var isUsingCachedFallback: Bool {
        bootstrapState == .degraded
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

        bootstrapState = .running
        errorMessage = nil
        let startedAt = Date()
        LinxDiagnostics.threadsModel.info("bootstrap start")

        do {
            let webID = try authController.webID()
            LinxDiagnostics.threadsModel.info("bootstrap webID resolved webID=\(webID, privacy: .private) webIDHash=\(LinxDiagnostics.fingerprint(webID), privacy: .public)")
            await loadCachedLaunchSnapshot(webID: webID)
            await runBootstrap(webID: webID, startedAt: startedAt)
        } catch is CancellationError {
            bootstrapState = .idle
            LinxDiagnostics.threadsModel.info("bootstrap cancelled")
        } catch {
            errorMessage = error.localizedDescription
            bootstrapState = .failed
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.threadsModel.error("bootstrap failed error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public) durationMs=\(durationMs, privacy: .public)")
        }
    }

    func retryBootstrap() async {
        guard authController.isAuthenticated, bootstrapState == .failed || bootstrapState == .degraded else { return }
        bootstrapState = .idle
        await bootstrapIfNeeded()
    }

    func dismissErrorMessage() {
        errorMessage = nil
    }

    private func runBootstrap(webID: String, startedAt: Date) async {
        do {
            async let preferredModelID = modelCatalogClient.preferredModelID()
            async let podBootstrap: Void = repository.bootstrap(
                webID: webID,
                modelID: AppConstants.defaultModelID,
                force: false
            )

            let resolvedModelID = try await preferredModelID
            try await podBootstrap
            activeModelID = resolvedModelID
            LinxDiagnostics.threadsModel.info("bootstrap model resolved modelID=\(self.activeModelID, privacy: .public)")
            LinxDiagnostics.threadsModel.info("bootstrap repository ready")
            let reloadResult = try await reloadThreads(selectFirstIfNeeded: true)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            if let degradation = reloadResult.degradation {
                errorMessage = degradation.message
                bootstrapState = .degraded
                LinxDiagnostics.threadsModel.error("bootstrap degraded using cache reason=\(degradation.message, privacy: .public) threads=\(self.threads.count, privacy: .public) selected=\(self.selectedThread?.id ?? "none", privacy: .private) selectedHash=\(LinxDiagnostics.fingerprint(self.selectedThread?.id), privacy: .public) messages=\(self.messages.count, privacy: .public) durationMs=\(durationMs, privacy: .public)")
                return
            }
            bootstrapState = .succeeded
            LinxDiagnostics.threadsModel.info("bootstrap succeeded threads=\(self.threads.count, privacy: .public) selected=\(self.selectedThread?.id ?? "none", privacy: .private) selectedHash=\(LinxDiagnostics.fingerprint(self.selectedThread?.id), privacy: .public) durationMs=\(durationMs, privacy: .public)")
        } catch is CancellationError {
            bootstrapState = .idle
            LinxDiagnostics.threadsModel.info("bootstrap cancelled")
        } catch {
            await finishBootstrapFailure(error, webID: webID, startedAt: startedAt)
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
        cachedLaunchThreadID = nil
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
        cachedLaunchThreadID = nil
    }

    func selectThread(_ thread: LinxThreadSummary) {
        invalidateMessageLoads()
        selectedThread = thread
        messages = []
        loadedMessageLimit = AppConstants.pageSize
        hasLoadedAllMessages = false
        isLoadingMessages = false
        isShowingThreadSheet = false
        cachedLaunchThreadID = nil

        Task {
            if let webID = try? authController.webID() {
                await loadCachedMessages(webID: webID, threadID: thread.id, limit: AppConstants.pageSize)
            }
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
        Task {
            await loadMoreMessagesPage()
        }
    }

    func loadMoreMessagesPage() async {
        guard canLoadMoreMessages else { return }
        loadedMessageLimit += AppConstants.pageSize
        await loadMessagesForCurrentThread()
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
            await persistMessagesCache(webID: webID, threadID: thread.id)

            let completionMessages = Self.makeCompletionMessages(
                history: persistedHistory,
                userMessage: userMessage,
                threadID: thread.id
            )

            let completion = try await runtimeService.createCompletionResult(
                messages: completionMessages,
                modelID: activeModelID,
                tools: []
            )
            let assistantMessage = try await repository.appendAssistantMessage(
                webID: webID,
                threadID: thread.id,
                content: completion.content
            )
            messages.append(assistantMessage)
            await persistMessagesCache(webID: webID, threadID: thread.id)
            _ = try await reloadThreads(selectFirstIfNeeded: false, reloadMessages: false)
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

    @discardableResult
    private func loadMessagesForCurrentThread() async -> MessageLoadResult {
        guard let selectedThread else { return .loaded }
        let threadID = selectedThread.id
        let requestedLimit = loadedMessageLimit
        let loadID = UUID()
        activeMessageLoadID = loadID
        isLoadingMessages = true

        let webID: String
        do {
            webID = try authController.webID()
        } catch {
            guard activeMessageLoadID == loadID, self.selectedThread?.id == threadID else { return .loaded }
            errorMessage = error.localizedDescription
            isLoadingMessages = false
            return .failed(error)
        }

        do {
            let loaded = try await repository.loadMessages(
                webID: webID,
                threadID: threadID,
                limit: requestedLimit,
                offset: 0
            )
            guard activeMessageLoadID == loadID, self.selectedThread?.id == threadID else { return .loaded }
            if loaded.isEmpty, shouldPreserveCurrentMessagesForEmptyRemote(threadID: threadID) {
                let degradation = SyncDegradation.emptyRemoteMessages
                errorMessage = degradation.message
                hasLoadedAllMessages = messages.count < requestedLimit
                isLoadingMessages = false
                LinxDiagnostics.threadsModel.error("messages remote empty preserving cache threadHash=\(LinxDiagnostics.fingerprint(threadID), privacy: .public) cachedMessages=\(self.messages.count, privacy: .public) limit=\(requestedLimit, privacy: .public)")
                return .preservedCache(degradation)
            }

            hasLoadedAllMessages = loaded.count < requestedLimit
            if cachedLaunchThreadID == threadID {
                messages = loaded
                cachedLaunchThreadID = nil
            } else {
                messages = mergedMessages(loaded, preserving: messages, threadID: threadID)
            }
            if loaded.isEmpty == false || messages.isEmpty {
                await persistMessagesCache(webID: webID, threadID: threadID)
            }
        } catch {
            guard activeMessageLoadID == loadID, self.selectedThread?.id == threadID else { return .loaded }
            errorMessage = error.localizedDescription
            if Self.shouldUseCacheFallback(for: error) {
                await loadCachedMessages(webID: webID, threadID: threadID, limit: requestedLimit)
            }
            if activeMessageLoadID == loadID {
                isLoadingMessages = false
            }
            return .failed(error)
        }

        if activeMessageLoadID == loadID {
            isLoadingMessages = false
        }
        return .loaded
    }

    @discardableResult
    private func reloadThreads(selectFirstIfNeeded: Bool, reloadMessages: Bool = true) async throws -> ThreadReloadResult {
        let webID = try authController.webID()
        let startedAt = Date()
        LinxDiagnostics.threadsModel.info("reloadThreads start selectFirst=\(selectFirstIfNeeded, privacy: .public) reloadMessages=\(reloadMessages, privacy: .public) previousCount=\(self.threads.count, privacy: .public) selected=\(self.selectedThread?.id ?? "none", privacy: .private) selectedHash=\(LinxDiagnostics.fingerprint(self.selectedThread?.id), privacy: .public) webID=\(webID, privacy: .private) webIDHash=\(LinxDiagnostics.fingerprint(webID), privacy: .public)")
        let loaded = try await repository.listThreads(webID: webID, limit: AppConstants.pageSize)
        let sortedThreads = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if sortedThreads.isEmpty, hasVisibleChatData {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let degradation = SyncDegradation.emptyRemoteThreads
            errorMessage = degradation.message
            isLoadingMessages = false
            LinxDiagnostics.threadsModel.error("reloadThreads remote empty preserving cache threads=\(self.threads.count, privacy: .public) selected=\(self.selectedThread?.id ?? "none", privacy: .private) selectedHash=\(LinxDiagnostics.fingerprint(self.selectedThread?.id), privacy: .public) messages=\(self.messages.count, privacy: .public) durationMs=\(durationMs, privacy: .public)")
            return ThreadReloadResult(degradation: degradation)
        }

        threads = sortedThreads
        await persistThreadsCache(webID: webID)
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        LinxDiagnostics.threadsModel.info("reloadThreads repository returned loaded=\(loaded.count, privacy: .public) sorted=\(self.threads.count, privacy: .public) durationMs=\(durationMs, privacy: .public)")

        if let selectedThread, let updated = threads.first(where: { $0.id == selectedThread.id }) {
            self.selectedThread = updated
            LinxDiagnostics.threadsModel.info("reloadThreads updated selected threadID=\(updated.id, privacy: .private) threadHash=\(LinxDiagnostics.fingerprint(updated.id), privacy: .public) reloadMessages=\(reloadMessages, privacy: .public)")
            if reloadMessages {
                switch await loadMessagesForCurrentThread() {
                case .loaded:
                    break
                case .preservedCache(let degradation):
                    return ThreadReloadResult(degradation: degradation)
                case .failed(let messageError):
                    throw messageError
                }
            }
            return .synced
        }

        if selectFirstIfNeeded, let first = threads.first {
            selectedThread = first
            hasLoadedAllMessages = false
            LinxDiagnostics.threadsModel.info("reloadThreads selected first threadID=\(first.id, privacy: .private) threadHash=\(LinxDiagnostics.fingerprint(first.id), privacy: .public)")
            switch await loadMessagesForCurrentThread() {
            case .loaded:
                break
            case .preservedCache(let degradation):
                return ThreadReloadResult(degradation: degradation)
            case .failed(let messageError):
                throw messageError
            }
            return .synced
        }

        if selectFirstIfNeeded {
            selectedThread = nil
            messages = []
            loadedMessageLimit = AppConstants.pageSize
            hasLoadedAllMessages = true
            isLoadingMessages = false
            cachedLaunchThreadID = nil
        }

        LinxDiagnostics.threadsModel.info("reloadThreads completed without selection threadCount=\(self.threads.count, privacy: .public) selectFirst=\(selectFirstIfNeeded, privacy: .public)")
        return .synced
    }

    private func finishBootstrapFailure(_ error: Error, webID: String, startedAt: Date) async {
        errorMessage = error.localizedDescription
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        if Self.shouldUseCacheFallback(for: error) {
            let didApplyCache = await loadCachedLaunchSnapshot(webID: webID)
            if didApplyCache || hasVisibleChatData {
                bootstrapState = .degraded
                LinxDiagnostics.threadsModel.error("bootstrap degraded using cache error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public) threads=\(self.threads.count, privacy: .public) messages=\(self.messages.count, privacy: .public) durationMs=\(durationMs, privacy: .public)")
                return
            }
        }

        bootstrapState = .failed
        LinxDiagnostics.threadsModel.error("bootstrap failed error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public) durationMs=\(durationMs, privacy: .public)")
    }

    private var hasVisibleChatData: Bool {
        threads.isEmpty == false || selectedThread != nil || messages.isEmpty == false
    }

    @discardableResult
    private func loadCachedLaunchSnapshot(webID: String) async -> Bool {
        do {
            guard let snapshot = try await localCache.loadLaunchSnapshot(webID: webID, limit: AppConstants.pageSize) else {
                return false
            }

            threads = snapshot.threads
            selectedThread = snapshot.selectedThread
            messages = snapshot.messages
            loadedMessageLimit = AppConstants.pageSize
            hasLoadedAllMessages = snapshot.selectedThread == nil || snapshot.messages.count < AppConstants.pageSize
            isLoadingMessages = false
            cachedLaunchThreadID = snapshot.selectedThread?.id
            LinxDiagnostics.threadsModel.info("bootstrap cache applied threads=\(snapshot.threads.count, privacy: .public) messages=\(snapshot.messages.count, privacy: .public) selectedHash=\(LinxDiagnostics.fingerprint(snapshot.selectedThread?.id), privacy: .public)")
            return true
        } catch {
            LinxDiagnostics.threadsModel.error("bootstrap cache ignored error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            return false
        }
    }

    @discardableResult
    private func loadCachedMessages(webID: String, threadID: String, limit: Int) async -> Bool {
        do {
            let cachedMessages = try await localCache.loadMessages(webID: webID, threadID: threadID, limit: limit)
            guard cachedMessages.isEmpty == false, selectedThread?.id == threadID else {
                return false
            }

            messages = cachedMessages
            hasLoadedAllMessages = cachedMessages.count < limit
            isLoadingMessages = false
            cachedLaunchThreadID = threadID
            LinxDiagnostics.threadsModel.info("messages cache applied threadHash=\(LinxDiagnostics.fingerprint(threadID), privacy: .public) messages=\(cachedMessages.count, privacy: .public)")
            return true
        } catch {
            LinxDiagnostics.threadsModel.error("messages cache ignored threadHash=\(LinxDiagnostics.fingerprint(threadID), privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
            return false
        }
    }

    private nonisolated static func shouldUseCacheFallback(for error: Error) -> Bool {
        if let appError = error as? LinxAppError {
            switch appError {
            case .authFailed, .missingWebID, .notAuthenticated:
                return false
            case .missingPresenter, .invalidIDToken, .invalidRuntimeResponse, .emptyModelCatalog,
                 .requestTimedOut, .podWriteFailed, .runtimeFailed:
                return true
            }
        }

        if let runtimeError = error as? LinxRuntimeRequestError, runtimeError.authExpired {
            return false
        }

        return true
    }

    private func persistThreadsCache(webID: String) async {
        do {
            try await localCache.saveThreads(threads, webID: webID)
        } catch {
            LinxDiagnostics.threadsModel.error("threads cache write failed error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
        }
    }

    private func persistMessagesCache(webID: String, threadID: String) async {
        do {
            try await localCache.saveMessages(messages, webID: webID, threadID: threadID)
        } catch {
            LinxDiagnostics.threadsModel.error("messages cache write failed threadID=\(threadID, privacy: .private) threadHash=\(LinxDiagnostics.fingerprint(threadID), privacy: .public) error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
        }
    }

    private func invalidateMessageLoads() {
        activeMessageLoadID = UUID()
    }

    private func shouldPreserveCurrentMessagesForEmptyRemote(threadID: String) -> Bool {
        messages.contains { $0.threadID == threadID }
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
