import ExyteChat
import Foundation

enum ExyteMessageAdapter {
    static func makeMessages(
        from messages: [LinxChatMessage],
        currentWebID: String?
    ) -> [Message] {
        messages.map { message in
            Message(
                id: message.id,
                user: makeUser(for: message, currentWebID: currentWebID),
                status: nil,
                createdAt: message.createdAt,
                text: message.content,
                customData: [
                    "role": message.role.rawValue,
                    "status": message.status.rawValue,
                ]
            )
        }
    }

    private static func makeUser(for message: LinxChatMessage, currentWebID: String?) -> User {
        switch message.role {
        case .user:
            return User(
                id: currentWebID ?? "current-user",
                name: "You",
                avatarURL: nil,
                isCurrentUser: true
            )
        case .assistant:
            return User(
                id: AppConstants.defaultAgentID,
                name: "LinX",
                avatarURL: nil,
                isCurrentUser: false
            )
        case .system:
            return User(
                id: "system",
                name: "System",
                avatarURL: nil,
                type: .system
            )
        }
    }
}
