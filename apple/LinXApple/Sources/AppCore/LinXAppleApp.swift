import SwiftUI

@main
struct LinXAppleApp: App {
    @StateObject private var authController: AuthSessionController
    @StateObject private var chatModel: ChatExperienceModel

    init() {
        let authController = AuthSessionController()
        _authController = StateObject(wrappedValue: authController)
        _chatModel = StateObject(wrappedValue: ChatExperienceModel(authController: authController))
    }

    var body: some Scene {
        WindowGroup {
            RootView(authController: authController, chatModel: chatModel)
                .onOpenURL { url in
                    authController.handleRedirect(url: url)
                }
        }
    }
}
