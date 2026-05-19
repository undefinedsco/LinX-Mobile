import ExyteChat
import SwiftUI

struct ChatScene: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: ChatExperienceModel
    let onLogout: () -> Void
    @State private var draftText = ""

    private var navigationTitle: String {
        viewModel.selectedThread?.title ?? "LinX"
    }

    private var navigationSubtitle: String {
        if viewModel.isSending {
            return "Responding"
        }
        if viewModel.isUsingCachedFallback {
            return "Cached Pod"
        }
        return viewModel.activeModelID
    }

    private var chatTheme: ChatTheme {
        LinxChatPalette.chatTheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            chatContent
        }
        .tint(LinxChatPalette.accent)
    }

    private var chatContent: some View {
        ChatView(messages: viewModel.exyteMessages, chatType: .conversation) { draft in
            send(draft)
        } messageBuilder: { params in
            if let domainMessage = viewModel.message(for: params.message.id), domainMessage.role == .assistant {
                AssistantMarkdownBubble(message: domainMessage)
                    .padding(.horizontal, 4)
            } else {
                params.defaultMessageView()
            }
        }
        .mainHeaderBuilder {
            LinxChatMainHeader(
                title: navigationTitle,
                modelID: viewModel.activeModelID,
                messageCount: viewModel.messages.count,
                isCached: viewModel.isUsingCachedFallback
            )
        }
        .betweenListAndInputViewBuilder {
            LinxSendingStatusBar(
                isVisible: viewModel.isSending,
                onCancel: viewModel.cancelSend
            )
        }
        .dateHeaderBuilder { date in
            LinxDateHeader(date: date)
        }
        .enableLoadMoreOlderMessages(
            triggerType: .pixels(64),
            hasMoreToLoad: viewModel.canLoadMoreMessages
        ) {
            await viewModel.loadMoreMessagesPage()
        } loadingIndicatorBuilder: {
            LinxChatLoadingIndicator()
        }
        .inputViewText($draftText)
        .keyboardDismissMode(.interactive)
        .setAvailableInputs([.text])
        .showAvatar(true)
        .showUsername(true)
        .avatarSize(avatarSize: 34)
        .avatarBuilder { user in
            LinxAvatarView(user: user)
        }
        .showDateHeaders(true)
        .showMessageMenuOnLongPress(false)
        .showNetworkConnectionProblem(false)
        .contentInsets(top: 10, bottom: 8, left: 8, right: 8)
        .chatTheme(chatTheme)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: showThreads) {
                    Image(systemName: "sidebar.left")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Show chats")
            }

            ToolbarItem(placement: .principal) {
                LinxChatToolbarTitle(
                    title: navigationTitle,
                    subtitle: navigationSubtitle,
                    isSending: viewModel.isSending
                )
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.isSending {
                    Button(role: .destructive, action: viewModel.cancelSend) {
                        Image(systemName: "stop.circle")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Cancel response")
                }

                Button(action: newChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("New chat")
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(LinxChatPalette.navigationBarBackground(for: colorScheme), for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = viewModel.errorMessage, error.isEmpty == false {
                LinxErrorBanner(
                    message: error,
                    canRetry: viewModel.canRetryBootstrap,
                    onRetry: retryBootstrap,
                    onDismiss: viewModel.dismissErrorMessage
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
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
        .background {
            LinxChatPalette.background(for: colorScheme)
                .ignoresSafeArea()
        }
    }

    private func send(_ draft: DraftMessage) {
        viewModel.enqueueSend(draft.text)
    }

    private func showThreads() {
        viewModel.isShowingThreadSheet = true
    }

    private func newChat() {
        draftText = ""
        viewModel.newChat()
    }

    private func retryBootstrap() {
        Task {
            await viewModel.retryBootstrap()
        }
    }
}

enum LinxChatPalette {
    static let accent = Color(red: 0.07, green: 0.46, blue: 0.41)
    static let blue = Color(red: 0.12, green: 0.36, blue: 0.70)
    static let warning = Color(red: 0.84, green: 0.24, blue: 0.18)

    static func background(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.04, green: 0.06, blue: 0.08),
                    Color(red: 0.06, green: 0.12, blue: 0.13),
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                ]
                : [
                    Color(red: 0.94, green: 0.97, blue: 0.96),
                    Color(red: 0.98, green: 0.98, blue: 0.94),
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func chatTheme(for colorScheme: ColorScheme) -> ChatTheme {
        let isDark = colorScheme == .dark
        let surface = isDark
            ? Color(red: 0.10, green: 0.13, blue: 0.15)
            : Color.white.opacity(0.94)
        let elevatedSurface = isDark
            ? Color(red: 0.13, green: 0.17, blue: 0.18)
            : Color(red: 0.96, green: 0.98, blue: 0.97)
        let foreground = isDark ? Color.white.opacity(0.94) : Color(red: 0.08, green: 0.11, blue: 0.13)
        let caption = isDark ? Color.white.opacity(0.62) : Color(red: 0.40, green: 0.46, blue: 0.48)

        return ChatTheme(
            colors: ChatTheme.Colors(
                mainBG: .clear,
                mainTint: accent,
                mainText: foreground,
                mainCaptionText: caption,
                messageMyBG: accent,
                messageReadStatus: Color.white.opacity(0.72),
                messageMyText: .white,
                messageMyTimeText: Color.white.opacity(0.62),
                messageFriendBG: elevatedSurface,
                messageFriendText: foreground,
                messageFriendTimeText: caption,
                messageSystemBG: surface,
                messageSystemText: caption,
                messageSystemTimeText: caption,
                inputBG: surface,
                inputText: foreground,
                inputPlaceholderText: caption,
                inputSignatureBG: surface,
                inputSignatureText: foreground,
                inputSignaturePlaceholderText: caption,
                menuBG: surface,
                menuText: foreground,
                menuTextDelete: warning,
                statusError: warning,
                statusGray: caption,
                sendButtonBackground: accent,
                recordDot: warning
            )
        )
    }

    static func navigationBarBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.05, green: 0.07, blue: 0.09).opacity(0.96)
            : Color(red: 0.97, green: 0.99, blue: 0.98).opacity(0.96)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    static func stroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.secondary
    }
}

private struct LinxChatToolbarTitle: View {
    let title: String
    let subtitle: String
    let isSending: Bool

    var body: some View {
        HStack(spacing: 9) {
            LinxAgentMark(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(isSending ? LinxChatPalette.blue : LinxChatPalette.accent)
                        .frame(width: 6, height: 6)
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: 220)
    }
}

private struct LinxChatMainHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let modelID: String
    let messageCount: Int
    let isCached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                LinxAgentMark(size: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(isCached ? "Cached Pod session" : "Pod session ready")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LinxChatPalette.secondaryText(for: colorScheme))
                }

                Spacer(minLength: 10)

                LinxSessionBadge(isCached: isCached)
            }

            HStack(spacing: 8) {
                LinxMetadataPill(systemImage: "text.bubble", text: "\(messageCount) messages")
                    .fixedSize(horizontal: true, vertical: false)
                LinxMetadataPill(systemImage: "cpu", text: modelID)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LinxChatPalette.stroke(for: colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct LinxMetadataPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(LinxChatPalette.secondaryText(for: colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(LinxChatPalette.surface(for: colorScheme))
            )
    }
}

private struct LinxSessionBadge: View {
    let isCached: Bool

    var body: some View {
        Label(isCached ? "Cache" : "Live", systemImage: isCached ? "externaldrive" : "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isCached ? LinxChatPalette.blue : LinxChatPalette.accent)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

private struct LinxSendingStatusBar: View {
    let isVisible: Bool
    let onCancel: () -> Void

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("LinX is responding")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive, action: onCancel) {
                        Image(systemName: "stop.circle")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel response")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial)
            }
        }
    }
}

private struct LinxDateHeader: View {
    let date: Date

    var body: some View {
        Text(date.formatted(date: .abbreviated, time: .omitted))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .padding(.vertical, 4)
    }
}

private struct LinxChatLoadingIndicator: View {
    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(LinxChatPalette.accent)
            .frame(width: 34, height: 34)
            .padding(.vertical, 10)
    }
}

private struct LinxAvatarView: View {
    let user: User

    private var isCurrentUser: Bool {
        user.isCurrentUser
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isCurrentUser ? LinxChatPalette.blue : LinxChatPalette.accent)

            Image(systemName: isCurrentUser ? "person.fill" : "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(user.name)
    }
}

private struct LinxAgentMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [LinxChatPalette.accent, LinxChatPalette.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: LinxChatPalette.accent.opacity(0.24), radius: 12, x: 0, y: 6)
    }
}

private struct LinxErrorBanner: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.bold))

            Text(message)
                .font(.footnote.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error message")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinxChatPalette.warning.opacity(0.94))
        )
        .shadow(color: LinxChatPalette.warning.opacity(0.22), radius: 14, x: 0, y: 8)
    }
}
