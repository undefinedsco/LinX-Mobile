import SwiftUI
import OSLog

struct ThreadListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let threads: [LinxThreadSummary]
    let selectedThreadID: String?
    let onSelect: (LinxThreadSummary) -> Void
    let onNewChat: () -> Void
    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: createNewChat) {
                        Label("New chat", systemImage: "square.and.pencil")
                            .font(.headline)
                            .foregroundStyle(LinxChatPalette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }

                Section("Chats") {
                    if threads.isEmpty {
                        ContentUnavailableView(
                            "No chats yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Start a new LinX conversation.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(threads) { thread in
                            Button {
                                select(thread)
                            } label: {
                                ThreadRow(
                                    thread: thread,
                                    isSelected: thread.id == selectedThreadID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background {
                LinxChatPalette.background(for: colorScheme)
                    .ignoresSafeArea()
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                LinxDiagnostics.threadsUI.debug("ThreadListView appear count=\(self.threads.count, privacy: .public) selected=\(self.selectedThreadID ?? "none", privacy: .private) selectedHash=\(LinxDiagnostics.fingerprint(self.selectedThreadID), privacy: .public)")
            }
            .onChange(of: threads.count) { _, newCount in
                LinxDiagnostics.threadsUI.debug("ThreadListView thread count changed count=\(newCount, privacy: .public) selected=\(self.selectedThreadID ?? "none", privacy: .private) selectedHash=\(LinxDiagnostics.fingerprint(self.selectedThreadID), privacy: .public)")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive, action: logout) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Logout")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createNewChat) {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(LinxChatPalette.navigationBarBackground(for: colorScheme), for: .navigationBar)
        }
    }

    private func select(_ thread: LinxThreadSummary) {
        onSelect(thread)
        dismiss()
    }

    private func createNewChat() {
        onNewChat()
        dismiss()
    }

    private func logout() {
        onLogout()
        dismiss()
    }
}

private struct ThreadRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let thread: LinxThreadSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isSelected ? LinxChatPalette.accent : LinxChatPalette.blue.opacity(0.16))
                Image(systemName: isSelected ? "checkmark" : "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : LinxChatPalette.blue)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(thread.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LinxChatPalette.secondaryText(for: colorScheme))
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
