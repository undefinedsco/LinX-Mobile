import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate, RNAppAuthAuthorizationFlowManager {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?
  weak var authorizationFlowManagerDelegate: RNAppAuthAuthorizationFlowManagerDelegate?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let delegate = ReactNativeDelegate()
    let factory = RCTReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory

    window = UIWindow(frame: UIScreen.main.bounds)

    let arguments = ProcessInfo.processInfo.arguments
    let isP2PSmoke = arguments.contains("--p2p-smoke")
    let moduleName = isP2PSmoke ? "LinXP2PSmoke" : "LinXMobile"
    let initialProperties = isP2PSmoke
      ? ["p2pSmokeDefaults": p2pSmokeDefaults(from: arguments)]
      : [:]

    factory.startReactNative(
      withModuleName: moduleName,
      in: window,
      initialProperties: initialProperties,
      launchOptions: launchOptions
    )

    return true
  }


  private func p2pSmokeDefaults(from arguments: [String]) -> [String: String] {
    var defaults: [String: String] = [:]
    copyArgument(arguments, into: &defaults, field: "localSpUrl", name: "--local-sp-url")
    copyArgument(arguments, into: &defaults, field: "idpUrl", name: "--idp-url")
    copyArgument(arguments, into: &defaults, field: "storageUrl", name: "--storage-url")
    copyArgument(arguments, into: &defaults, field: "apiBaseUrl", name: "--api-base-url")
    copyArgument(arguments, into: &defaults, field: "nodeId", name: "--node-id")
    copyArgument(arguments, into: &defaults, field: "clientId", name: "--client-id")
    copyArgument(arguments, into: &defaults, field: "resourcePath", name: "--resource-path")
    copyArgument(arguments, into: &defaults, field: "updateManifestUrl", name: "--update-manifest-url")
    return defaults
  }

  private func copyArgument(
    _ arguments: [String],
    into defaults: inout [String: String],
    field: String,
    name: String
  ) {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return
    }
    let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty {
      defaults[field] = value
    }
  }

  func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if let authorizationFlowManagerDelegate,
       authorizationFlowManagerDelegate.resumeExternalUserAgentFlow(with: url) {
      return true
    }

    return false
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
#else
    Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}
