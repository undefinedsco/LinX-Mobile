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
                    }
            case .unauthenticated:
                LoginView(
                    isBusy: false,
                    errorMessage: authController.lastErrorMessage,
                    onLogin: {
                        Task {
                            chatModel.resetForLogout()
                            await authController.login()
                        }
                    }
                )
            case .authenticating:
                LoginView(
                    isBusy: true,
                    errorMessage: authController.lastErrorMessage,
                    onLogin: {}
                )
            case .authenticated:
                ChatScene(viewModel: chatModel) {
                    chatModel.resetForLogout()
                    authController.logout()
                }
                .task {
                    if chatModel.needsBootstrap {
                        await chatModel.bootstrapIfNeeded()
                    }
                }
                .overlay {
                    if chatModel.isBootstrapping {
                        ProgressView("Syncing your Pod…")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
            }
        }
        .tint(Color(red: 0.07, green: 0.46, blue: 0.41))
    }
}
