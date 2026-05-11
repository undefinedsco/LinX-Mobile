import MarkdownView
import SwiftUI

struct AssistantMarkdownBubble: View {
    let message: LinxChatMessage

    private var bodyText: String {
        if message.content.isEmpty, message.status == .streaming {
            return "Thinking..."
        }
        return message.content.isEmpty ? "No content" : message.content
    }

    private var sanitizedMarkdown: String {
        bodyText.replacingOccurrences(
            of: #"!?\[[^\]]*\]\((https?://[^)\s]+)\)"#,
            with: "[Open image]($1)",
            options: .regularExpression
        )
    }

    private var statusLine: String? {
        switch message.status {
        case .streaming:
            return "Streaming"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LinX")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if message.status == .streaming {
                Text(bodyText)
                    .textSelection(.enabled)
            } else {
                MarkdownView(sanitizedMarkdown)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if message.status == .streaming {
                    ProgressView()
                        .controlSize(.mini)
                }
                if let statusLine {
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.95, green: 0.96, blue: 0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button("Copy") {
                UIPasteboard.general.string = message.content
            }
        }
    }
}
