import Foundation
@preconcurrency import SwiftOpenAI

@MainActor
struct LinxOpenAIChatService {
    let authController: AuthSessionController

    func streamReply(
        messages: [LinxChatMessage],
        modelID: String,
        onDelta: @escaping (String) async throws -> Void
    ) async throws -> String {
        let accessToken = try await authController.accessToken()
        let service = OpenAIServiceFactory.service(
            apiKey: accessToken,
            overrideBaseURL: AppConstants.runtimeBaseURL.absoluteString,
            overrideVersion: AppConstants.runtimeVersion
        )
        let parameters = ChatCompletionParameters(
            messages: messages.map(Self.makeMessage),
            model: .custom(modelID)
        )

        do {
            let stream = try await service.startStreamedChat(parameters: parameters)
            var accumulated = ""
            for try await chunk in stream {
                guard let delta = chunk.choices?.first?.delta?.content, delta.isEmpty == false else {
                    continue
                }
                accumulated += delta
                try await onDelta(accumulated)
            }
            return accumulated
        } catch {
            let completion = try await service.startChat(parameters: parameters)
            let content = completion.choices?.first?.message?.content ?? ""
            try await onDelta(content)
            return content
        }
    }

    private static func makeMessage(_ message: LinxChatMessage) -> ChatCompletionParameters.Message {
        ChatCompletionParameters.Message(
            role: .init(rawValue: message.role.rawValue) ?? .user,
            content: .text(message.content)
        )
    }
}
