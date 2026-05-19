import CryptoKit
import Foundation
import OSLog

enum LinxDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "co.undefineds.linx.apple"

    static let threadsUI = Logger(subsystem: subsystem, category: "threads.ui")
    static let threadsModel = Logger(subsystem: subsystem, category: "threads.model")
    static let podRepository = Logger(subsystem: subsystem, category: "pod.repository")
    static let podNetwork = Logger(subsystem: subsystem, category: "pod.network")
    static let runtime = Logger(subsystem: subsystem, category: "runtime")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let speech = Logger(subsystem: subsystem, category: "speech")

    nonisolated static func fingerprint(_ value: String?) -> String {
        guard
            let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            normalized.isEmpty == false
        else {
            return "empty"
        }

        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func fingerprint(url: URL?) -> String {
        fingerprint(url?.absoluteString)
    }
}
