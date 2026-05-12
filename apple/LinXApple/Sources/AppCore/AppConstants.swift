import Foundation

enum AppConstants {
    static let appName = LinxSharedContract.Defaults.appName
    static let bundleIdentifier = LinxSharedContract.Defaults.bundleIdentifier

    static let issuerURL = LinxSharedContract.Runtime.issuerURL
    static let discoveryURL = LinxSharedContract.Runtime.discoveryURL
    static let runtimeBaseURL = LinxSharedContract.Runtime.runtimeBaseURL
    static let runtimeVersion = LinxSharedContract.Runtime.apiVersion

    static let redirectURL = URL(string: "co.undefineds.linx.apple://auth/callback")!
    static let loginScopes = ["openid", "offline_access", "webid"]

    static let defaultModelID = LinxSharedContract.Defaults.defaultModelID
    static let defaultChatID = LinxSharedContract.Defaults.defaultChatID
    static let defaultAgentID = LinxSharedContract.Defaults.defaultAgentID
    static let defaultChatTitle = LinxSharedContract.Defaults.defaultChatTitle
    static let defaultAgentName = LinxSharedContract.Defaults.defaultAgentName
    static let defaultThreadTitle = LinxSharedContract.Defaults.defaultThreadTitle
    static let defaultThreadWorkspace = LinxSharedContract.Defaults.defaultThreadWorkspace
    static let loginExpiredMessage = "LinX Cloud login expired."

    static let pageSize = 20
    static let podRequestTimeout: TimeInterval = 20
    static let runtimeRequestTimeout: TimeInterval = 30
    static let tokenRefreshTimeout: TimeInterval = 30
}
