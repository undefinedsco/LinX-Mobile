#if DEBUG
import Foundation
import OSLog

enum LinxDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "co.undefineds.linx.apple"

    static let threadsUI = Logger(subsystem: subsystem, category: "threads.ui")
    static let threadsModel = Logger(subsystem: subsystem, category: "threads.model")
    static let podRepository = Logger(subsystem: subsystem, category: "pod.repository")
    static let podNetwork = Logger(subsystem: subsystem, category: "pod.network")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
#endif
