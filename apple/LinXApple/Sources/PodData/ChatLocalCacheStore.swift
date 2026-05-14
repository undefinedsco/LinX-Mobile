import CryptoKit
import Foundation

enum LocalPodFileStore {
    static func webIDHash(_ webID: String) -> String {
        let digest = SHA256.hash(data: Data(webID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func applicationSupportDirectory(appending pathComponents: [String]) throws -> URL {
        guard var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LinxAppError.podWriteFailed("Application Support directory is unavailable.")
        }

        for component in pathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        setNoBackup(url)
        setFileProtection(url)
    }

    static func setNoBackup(_ url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }

    static func setFileProtection(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    static func safeFileNameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let candidate = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return candidate.isEmpty ? webIDHash(value) : candidate
    }
}
struct ChatCacheLaunchSnapshot: Sendable {
    let threads: [LinxThreadSummary]
    let selectedThread: LinxThreadSummary?
    let messages: [LinxChatMessage]
}

actor ChatLocalCacheStore {
    private static let schemaVersion = 1

    private struct CachedThreadsEnvelope: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let webIDHash: String
        let threads: [LinxThreadSummary]
    }

    private struct CachedMessagesEnvelope: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let webIDHash: String
        let threadID: String
        let messages: [LinxChatMessage]
    }

    private let rootDirectory: URL?

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
    }

    func loadLaunchSnapshot(webID: String, limit: Int) async throws -> ChatCacheLaunchSnapshot? {
        let webIDHash = LocalPodFileStore.webIDHash(webID)
        let userDirectory = try userCacheDirectory(webIDHash: webIDHash, createIfNeeded: false)
        let threadsURL = userDirectory.appendingPathComponent("threads.json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: threadsURL.path) else {
            return nil
        }

        let threadsData = try Data(contentsOf: threadsURL)
        let threadsEnvelope = try JSONDecoder().decode(CachedThreadsEnvelope.self, from: threadsData)
        guard threadsEnvelope.schemaVersion == Self.schemaVersion, threadsEnvelope.webIDHash == webIDHash else {
            return nil
        }

        let threads = Array(
            threadsEnvelope.threads
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit)
        )
        guard threads.isEmpty == false else {
            return nil
        }

        let selectedThread = threads.first
        let messages: [LinxChatMessage]
        if let selectedThread {
            messages = try loadMessages(webIDHash: webIDHash, threadID: selectedThread.id, limit: limit)
        } else {
            messages = []
        }

        return ChatCacheLaunchSnapshot(
            threads: threads,
            selectedThread: selectedThread,
            messages: messages
        )
    }

    func saveThreads(_ threads: [LinxThreadSummary], webID: String) async throws {
        let webIDHash = LocalPodFileStore.webIDHash(webID)
        let userDirectory = try userCacheDirectory(webIDHash: webIDHash, createIfNeeded: true)
        let threadsURL = userDirectory.appendingPathComponent("threads.json", isDirectory: false)
        let envelope = CachedThreadsEnvelope(
            schemaVersion: Self.schemaVersion,
            cachedAt: Date(),
            webIDHash: webIDHash,
            threads: Array(threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(AppConstants.pageSize))
        )

        try write(envelope, to: threadsURL)
    }

    func saveMessages(_ messages: [LinxChatMessage], webID: String, threadID: String) async throws {
        let webIDHash = LocalPodFileStore.webIDHash(webID)
        let userDirectory = try userCacheDirectory(webIDHash: webIDHash, createIfNeeded: true)
        let messagesURL = messagesCacheURL(userDirectory: userDirectory, threadID: threadID)
        let sortedMessages = messages.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
        let envelope = CachedMessagesEnvelope(
            schemaVersion: Self.schemaVersion,
            cachedAt: Date(),
            webIDHash: webIDHash,
            threadID: threadID,
            messages: Array(sortedMessages.suffix(AppConstants.pageSize))
        )

        try write(envelope, to: messagesURL)
    }

    func clearUserCache(webID: String) async throws {
        let webIDHash = LocalPodFileStore.webIDHash(webID)
        let userDirectory = try userCacheDirectory(webIDHash: webIDHash, createIfNeeded: false)
        guard FileManager.default.fileExists(atPath: userDirectory.path) else {
            return
        }
        try FileManager.default.removeItem(at: userDirectory)
    }

    private func loadMessages(webIDHash: String, threadID: String, limit: Int) throws -> [LinxChatMessage] {
        let userDirectory = try userCacheDirectory(webIDHash: webIDHash, createIfNeeded: false)
        let messagesURL = messagesCacheURL(userDirectory: userDirectory, threadID: threadID)
        guard FileManager.default.fileExists(atPath: messagesURL.path) else {
            return []
        }

        let data = try Data(contentsOf: messagesURL)
        let envelope = try JSONDecoder().decode(CachedMessagesEnvelope.self, from: data)
        guard
            envelope.schemaVersion == Self.schemaVersion,
            envelope.webIDHash == webIDHash,
            envelope.threadID == threadID
        else {
            return []
        }

        let sortedMessages = envelope.messages.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
        return Array(sortedMessages.suffix(limit))
    }

    private func userCacheDirectory(webIDHash: String, createIfNeeded: Bool) throws -> URL {
        let root = try rootCacheDirectory(createIfNeeded: createIfNeeded)
        let userDirectory = root.appendingPathComponent(webIDHash, isDirectory: true)
        if createIfNeeded {
            try LocalPodFileStore.ensureDirectory(userDirectory)
        }
        return userDirectory
    }

    private func rootCacheDirectory(createIfNeeded: Bool) throws -> URL {
        let root = try rootDirectory ?? LocalPodFileStore.applicationSupportDirectory(
            appending: ["LinXApple", "chat-cache"]
        )
        if createIfNeeded {
            try LocalPodFileStore.ensureDirectory(root)
        }
        return root
    }

    private func messagesCacheURL(userDirectory: URL, threadID: String) -> URL {
        userDirectory.appendingPathComponent(
            "messages-\(LocalPodFileStore.safeFileNameComponent(threadID)).json",
            isDirectory: false
        )
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
        LocalPodFileStore.setNoBackup(url)
        LocalPodFileStore.setFileProtection(url)
    }
}
