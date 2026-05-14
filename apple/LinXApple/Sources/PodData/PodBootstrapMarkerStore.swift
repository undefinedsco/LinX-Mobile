import Foundation

struct PodBootstrapMarker: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let webIDHash: String
    let chatID: String
    let resourceLayoutVersion: Int
    let completedAt: Date
}

actor PodBootstrapMarkerStore {
    private static let schemaVersion = 1
    private static let resourceLayoutVersion = 1

    private let rootDirectory: URL?

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
    }

    func hasCompletedBootstrap(webID: String, chatID: String = AppConstants.defaultChatID) async -> Bool {
        do {
            let webIDHash = LocalPodFileStore.webIDHash(webID)
            let url = try markerURL(webIDHash: webIDHash, chatID: chatID, createIfNeeded: false)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return false
            }

            let data = try Data(contentsOf: url)
            let marker = try JSONDecoder().decode(PodBootstrapMarker.self, from: data)
            return marker.schemaVersion == Self.schemaVersion
                && marker.resourceLayoutVersion == Self.resourceLayoutVersion
                && marker.webIDHash == webIDHash
                && marker.chatID == chatID
        } catch {
            return false
        }
    }

    func markCompleted(webID: String, chatID: String = AppConstants.defaultChatID) async throws {
        let webIDHash = LocalPodFileStore.webIDHash(webID)
        let url = try markerURL(webIDHash: webIDHash, chatID: chatID, createIfNeeded: true)
        let marker = PodBootstrapMarker(
            schemaVersion: Self.schemaVersion,
            webIDHash: webIDHash,
            chatID: chatID,
            resourceLayoutVersion: Self.resourceLayoutVersion,
            completedAt: Date()
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(to: url, options: [.atomic])
        LocalPodFileStore.setNoBackup(url)
        LocalPodFileStore.setFileProtection(url)
    }

    private func markerURL(webIDHash: String, chatID: String, createIfNeeded: Bool) throws -> URL {
        let root = try rootMarkerDirectory(createIfNeeded: createIfNeeded)
        return root.appendingPathComponent(
            "\(webIDHash)-\(LocalPodFileStore.safeFileNameComponent(chatID)).json",
            isDirectory: false
        )
    }

    private func rootMarkerDirectory(createIfNeeded: Bool) throws -> URL {
        let root = try rootDirectory ?? LocalPodFileStore.applicationSupportDirectory(
            appending: ["LinXApple", "pod-bootstrap"]
        )
        if createIfNeeded {
            try LocalPodFileStore.ensureDirectory(root)
        }
        return root
    }
}
