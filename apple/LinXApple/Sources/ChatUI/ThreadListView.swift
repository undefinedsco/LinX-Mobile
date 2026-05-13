import SwiftUI
#if DEBUG
import OSLog
#endif

struct ThreadListView: View {
    let threads: [LinxThreadSummary]
    let selectedThreadID: String?
    let onSelect: (LinxThreadSummary) -> Void
    let onNewChat: () -> Void
    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List(threads) { thread in
                Button {
                    onSelect(thread)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if thread.id == selectedThreadID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.07, green: 0.46, blue: 0.41))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Threads")
#if DEBUG
            .onAppear {
                LinxDiagnostics.threadsUI.debug("ThreadListView appear count=\(self.threads.count, privacy: .public) selected=\(self.selectedThreadID ?? "none", privacy: .private)")
            }
            .onChange(of: threads.count) { _, newCount in
                LinxDiagnostics.threadsUI.debug("ThreadListView thread count changed count=\(newCount, privacy: .public) selected=\(self.selectedThreadID ?? "none", privacy: .private)")
            }
#endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Logout", role: .destructive, action: onLogout)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Chat", action: onNewChat)
                }
            }
        }
    }
}
