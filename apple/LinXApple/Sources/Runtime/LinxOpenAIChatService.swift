import Foundation

@MainActor
protocol LinxRuntimeAuthProviding: AnyObject {
    func accessToken(forceRefresh: Bool) async throws -> String
    func expireSession(message: String)
}

extension AuthSessionController: LinxRuntimeAuthProviding {}

struct LinxHTTPTransport: Sendable {
    let data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = LinxHTTPTransport { request in
        try await URLSession.shared.data(for: request)
    }
}

struct RemoteCompletionResult: Equatable, Sendable {
    let content: String
    let reasoningContent: String?
    let toolCalls: [RemoteChatToolCall]
    let finishReason: String?
    let usage: RemoteCompletionUsage?
}

struct RemoteCompletionUsage: Equatable, Sendable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let totalTokens: Int
}

struct RemoteChatToolCall: Decodable, Equatable, Sendable {
    struct Function: Decodable, Equatable, Sendable {
        let name: String
        let arguments: String
    }

    let id: String
    let type: String
    let function: Function
}

struct RemoteChatTool: Encodable, Equatable, Sendable {
    struct Function: Encodable, Equatable, Sendable {
        let name: String
        let description: String?
        let parameters: JSONValue?
    }

    let type: String
    let function: Function
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct RemoteChatRequestMessage: Encodable, Equatable, Sendable {
    let role: String
    let content: String
}

struct RemoteChatCompletionRequest: Encodable, Equatable, Sendable {
    let model: String
    let stream: Bool
    let messages: [RemoteChatRequestMessage]
    let tools: [RemoteChatTool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case messages
        case tools
        case toolChoice = "tool_choice"
    }

    init(model: String, messages: [RemoteChatRequestMessage], tools: [RemoteChatTool]? = nil) {
        self.model = model
        self.stream = false
        self.messages = messages
        self.tools = tools?.isEmpty == false ? tools : nil
        self.toolChoice = tools?.isEmpty == false ? "auto" : nil
    }
}

@MainActor
struct LinxOpenAIChatService {
    let authProvider: LinxRuntimeAuthProviding
    let transport: LinxHTTPTransport
    let runtimeBaseURL: URL
    let runtimeVersion: String

    init(
        authController: AuthSessionController,
        transport: LinxHTTPTransport = .shared,
        runtimeBaseURL: URL = AppConstants.runtimeBaseURL,
        runtimeVersion: String = AppConstants.runtimeVersion
    ) {
        self.authProvider = authController
        self.transport = transport
        self.runtimeBaseURL = runtimeBaseURL
        self.runtimeVersion = runtimeVersion
    }

    init(
        authProvider: LinxRuntimeAuthProviding,
        transport: LinxHTTPTransport = .shared,
        runtimeBaseURL: URL = AppConstants.runtimeBaseURL,
        runtimeVersion: String = AppConstants.runtimeVersion
    ) {
        self.authProvider = authProvider
        self.transport = transport
        self.runtimeBaseURL = runtimeBaseURL
        self.runtimeVersion = runtimeVersion
    }

    func createCompletionResult(
        messages: [LinxChatMessage],
        modelID: String,
        tools: [RemoteChatTool] = []
    ) async throws -> RemoteCompletionResult {
        let requestBody = Self.makeRequestBody(messages: messages, modelID: modelID, tools: tools)

        do {
            return try await sendCompletion(requestBody: requestBody, forceRefresh: false)
        } catch let error as LinxRuntimeRequestError where error.authExpired {
            do {
                return try await sendCompletion(requestBody: requestBody, forceRefresh: true)
            } catch let refreshedError as LinxRuntimeRequestError where refreshedError.authExpired {
                authProvider.expireSession(message: AppConstants.loginExpiredMessage)
                throw LinxAppError.authFailed(AppConstants.loginExpiredMessage)
            }
        }
    }

    nonisolated static func makeRequestBody(
        messages: [LinxChatMessage],
        modelID: String,
        tools: [RemoteChatTool] = []
    ) -> RemoteChatCompletionRequest {
        RemoteChatCompletionRequest(
            model: modelID.isEmpty ? AppConstants.defaultModelID : modelID,
            messages: messages.map { message in
                RemoteChatRequestMessage(role: message.role.rawValue, content: message.content)
            },
            tools: tools
        )
    }

    nonisolated static func makeURLRequest(
        runtimeBaseURL: URL,
        runtimeVersion: String,
        apiKey: String,
        body: RemoteChatCompletionRequest
    ) throws -> URLRequest {
        let url = LinxSharedContract.Runtime.endpoint(
            runtimeBaseURL: runtimeBaseURL,
            version: runtimeVersion,
            path: "chat/completions"
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func sendCompletion(
        requestBody: RemoteChatCompletionRequest,
        forceRefresh: Bool
    ) async throws -> RemoteCompletionResult {
        let token = try await authProvider.accessToken(forceRefresh: forceRefresh)
        let request = try Self.makeURLRequest(
            runtimeBaseURL: runtimeBaseURL,
            runtimeVersion: runtimeVersion,
            apiKey: token,
            body: requestBody
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LinxRuntimeRequestError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return try Self.decodeCompletionResult(from: data)
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw LinxRuntimeRequestError.http(status: httpResponse.statusCode, responseBody: body)
        }

        return try Self.decodeCompletionResult(from: data)
    }

    nonisolated static func decodeCompletionResult(from data: Data) throws -> RemoteCompletionResult {
        let json = try JSONDecoder().decode(RemoteChatCompletionResponse.self, from: data)
        guard let choice = json.choices.first, let message = choice.message else {
            throw LinxAppError.invalidRuntimeResponse
        }

        let content = message.content?.normalized ?? ""
        let reasoningContent = message.reasoningContent ?? message.reasoning ?? message.reasoningText
        let normalizedReasoning = reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolCalls = message.toolCalls ?? []
        let usage = Self.normalizeUsage(json.usage ?? choice.usage)

        if content.isEmpty, normalizedReasoning?.isEmpty != false, toolCalls.isEmpty {
            throw LinxAppError.runtimeFailed("Empty response from remote model")
        }

        return RemoteCompletionResult(
            content: content,
            reasoningContent: normalizedReasoning?.isEmpty == false ? normalizedReasoning : nil,
            toolCalls: toolCalls,
            finishReason: choice.finishReason,
            usage: usage
        )
    }

    nonisolated private static func normalizeUsage(_ raw: RemoteCompletionRawUsage?) -> RemoteCompletionUsage? {
        guard let raw else { return nil }

        let promptTokens = nonNegative(raw.promptTokens)
        let reportedCachedTokens = nonNegative(raw.promptTokensDetails?.cachedTokens)
        let cacheWrite = nonNegative(raw.promptTokensDetails?.cacheWriteTokens)
        let cacheRead = cacheWrite > 0 ? max(0, reportedCachedTokens - cacheWrite) : reportedCachedTokens
        let input = max(0, promptTokens - cacheRead - cacheWrite)
        let output = nonNegative(raw.completionTokens) + nonNegative(raw.completionTokensDetails?.reasoningTokens)
        let computedTotal = input + output + cacheRead + cacheWrite

        return RemoteCompletionUsage(
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            totalTokens: computedTotal > 0 ? computedTotal : nonNegative(raw.totalTokens)
        )
    }

    nonisolated private static func nonNegative(_ value: Int?) -> Int {
        guard let value, value > 0 else { return 0 }
        return value
    }
}

private struct RemoteChatCompletionResponse: Decodable {
    let usage: RemoteCompletionRawUsage?
    let choices: [Choice]

    struct Choice: Decodable {
        let finishReason: String?
        let usage: RemoteCompletionRawUsage?
        let message: Message?

        enum CodingKeys: String, CodingKey {
            case finishReason = "finish_reason"
            case usage
            case message
        }
    }

    struct Message: Decodable {
        let content: RemoteChatResponseContent?
        let reasoningContent: String?
        let reasoning: String?
        let reasoningText: String?
        let toolCalls: [RemoteChatToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
            case reasoning
            case reasoningText = "reasoning_text"
            case toolCalls = "tool_calls"
        }
    }
}

private enum RemoteChatResponseContent: Decodable {
    struct Part: Decodable {
        let text: String?
    }

    case string(String)
    case parts([Part])
    case null

    var normalized: String {
        switch self {
        case .string(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .parts(let parts):
            return parts.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        case .null:
            return ""
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .parts(try container.decode([Part].self))
        }
    }
}

private struct RemoteCompletionRawUsage: Decodable {
    struct PromptDetails: Decodable {
        let cachedTokens: Int?
        let cacheWriteTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
            case cacheWriteTokens = "cache_write_tokens"
        }
    }

    struct CompletionDetails: Decodable {
        let reasoningTokens: Int?

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let promptTokensDetails: PromptDetails?
    let completionTokensDetails: CompletionDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }
}
