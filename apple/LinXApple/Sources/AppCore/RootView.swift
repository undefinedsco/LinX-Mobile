import SwiftUI

struct RootView: View {
    @ObservedObject var authController: AuthSessionController
    @ObservedObject var chatModel: ChatExperienceModel

    var body: some View {
        Group {
            switch authController.phase {
            case .launching:
                ProgressView("Preparing LinX…")
                    .task {
                        await authController.restore()
                        await chatModel.bootstrapIfNeeded()
                    }
            case .unauthenticated:
                LoginView(
                    isBusy: false,
                    errorMessage: authController.lastErrorMessage,
                    onLogin: {
                        Task {
                            await authController.login()
                            await chatModel.bootstrapIfNeeded()
                        }
                    }
                )
            case .authenticated:
                if chatModel.isBootstrapping {
                    ProgressView("Syncing your Pod…")
                } else {
                    ChatScene(viewModel: chatModel) {
                        chatModel.resetForLogout()
                        authController.logout()
                    }
                    .task {
                        await chatModel.bootstrapIfNeeded()
                    }
                }
            }
        }
        .tint(Color(red: 0.07, green: 0.46, blue: 0.41))
    }
}
