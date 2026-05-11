import ExyteChat
import SwiftUI

struct ChatScene: View {
    @ObservedObject var viewModel: ChatExperienceModel
    let onLogout: () -> Void

    private var navigationTitle: String {
        viewModel.selectedThread?.title ?? "LinX"
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
                            viewModel.cancelStreaming()
                        }
                    }
                    Button("New Chat") {
                        viewModel.newChat()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.errorMessage, error.isEmpty == false {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.92))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.canRetryLastUserMessage {
                    HStack {
                        Spacer()
                        Button("Retry Last Message") {
                            viewModel.retryLastUserMessage()
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.95, green: 0.96, blue: 0.93), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(.clear)
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
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.95),
                        Color.white,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }
}
