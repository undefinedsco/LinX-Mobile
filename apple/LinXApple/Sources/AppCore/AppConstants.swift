import Foundation

enum AppConstants {
    static let appName = "LinX Apple"
    static let bundleIdentifier = "co.undefineds.linx.apple"

    static let issuerURL = URL(string: "https://id.undefineds.co")!
    static let discoveryURL = URL(string: "https://id.undefineds.co/.well-known/openid-configuration")!
    static let runtimeBaseURL = URL(string: "https://api.undefineds.co")!
    static let runtimeVersion = "v1"

    static let redirectURL = URL(string: "co.undefineds.linx.apple://auth/callback")!
    static let loginScopes = ["openid", "offline_access", "webid"]

    static let defaultModelID = "linx-lite"
    static let defaultChatID = "cli-default"
    static let defaultAgentID = "linx-cli-assistant"
    static let defaultChatTitle = "LinX CLI"
    static let defaultAgentName = "LinX CLI Assistant"
    static let defaultThreadTitle = "iOS Session"

    static let pageSize = 20
    static let streamPatchIntervalNanoseconds: UInt64 = 200_000_000
}
