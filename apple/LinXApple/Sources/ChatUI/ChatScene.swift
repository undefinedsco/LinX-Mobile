import ExyteChat
import SwiftUI

struct ChatScene: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: ChatExperienceModel
    let onLogout: () -> Void

    private var navigationTitle: String {
        viewModel.selectedThread?.title ?? "LinX"
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.06, green: 0.08, blue: 0.11),
                    Color(red: 0.03, green: 0.06, blue: 0.09),
                ]
                : [
                    Color(red: 0.98, green: 0.98, blue: 0.95),
                    Color.white,
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        NavigationStack {
            ChatView(messages: viewModel.exyteMessages) { draft in
                viewModel.enqueueSend(draft.text)
            } messageBuilder: { params in
                if let domainMessage = viewModel.message(for: params.message.id), domainMessage.role == .assistant {
                    AssistantMarkdownBubble(message: domainMessage)
                        .padding(.horizontal, 4)
                } else {
                    params.defaultMessageView()
                }
            }
            .setAvailableInputs([.text])
            .enableLoadMore(offset: 0) {
                viewModel.loadMoreMessages()
            }
            .showMessageMenuOnLongPress(false)
            .showNetworkConnectionProblem(false)
            .showAvatar(false)
            .showDateHeaders(true)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.isShowingThreadSheet = true
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isSending {
                        Button("Cancel", role: .destructive) {
                            viewModel.cancelSend()
                        }
                    }
                    Button("New Chat") {
                        viewModel.newChat()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.errorMessage, error.isEmpty == false {
                    HStack(spacing: 12) {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if viewModel.canRetryBootstrap {
                            Button("Retry") {
                                Task {
                                    await viewModel.retryBootstrap()
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                        }

                        Button {
                            viewModel.dismissErrorMessage()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.bold))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Dismiss error message")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.92))
                }
            }
            .sheet(isPresented: $viewModel.isShowingThreadSheet) {
                ThreadListView(
                    threads: viewModel.threads,
                    selectedThreadID: viewModel.selectedThread?.id,
                    onSelect: viewModel.selectThread,
                    onNewChat: viewModel.newChat,
                    onLogout: onLogout
                )
            }
            .background(
                backgroundGradient
                .ignoresSafeArea()
            )
        }
    }
}
