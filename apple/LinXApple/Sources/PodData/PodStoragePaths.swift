import Foundation

enum PodStoragePaths {
    static func podBaseURL(forWebID webID: String) throws -> URL {
        guard var components = URLComponents(string: webID) else {
            throw LinxAppError.missingWebID
        }

        components.fragment = nil

        if components.path.hasSuffix("/profile/card") {
            components.path = String(components.path.dropLast("/profile/card".count))
        } else {
            components.path = components.path.replacingOccurrences(of: "/card", with: "")
        }

        guard let url = components.url else {
            throw LinxAppError.missingWebID
        }

        if url.path.isEmpty {
            var rootComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            rootComponents?.path = "/"
            return rootComponents?.url ?? url
        }

        return url.absoluteString.hasSuffix("/")
            ? url
            : URL(string: url.absoluteString + "/")!
    }

    static func dataContainer(baseURL: URL) -> URL {
        baseURL.appendingPathComponent(LinxSharedContract.Resource.dataContainerName, isDirectory: true)
    }

    static func chatRootContainer(baseURL: URL) -> URL {
        dataContainer(baseURL: baseURL)
            .appendingPathComponent(LinxSharedContract.Resource.chatContainerName, isDirectory: true)
    }

    static func chatContainer(baseURL: URL, chatID: String) -> URL {
        chatRootContainer(baseURL: baseURL).appendingPathComponent(chatID, isDirectory: true)
    }

    static func chatIndexResource(baseURL: URL, chatID: String) -> URL {
        chatContainer(baseURL: baseURL, chatID: chatID)
            .appendingPathComponent(LinxSharedContract.Resource.chatIndexFileName, isDirectory: false)
    }

    static func agentsContainer(baseURL: URL) -> URL {
        dataContainer(baseURL: baseURL)
            .appendingPathComponent(LinxSharedContract.Resource.agentsContainerName, isDirectory: true)
    }

    static func agentResource(baseURL: URL, agentID: String) -> URL {
        agentsContainer(baseURL: baseURL)
            .appendingPathComponent("\(agentID).\(LinxSharedContract.Resource.agentFileExtension)", isDirectory: false)
    }

    static func messageContainers(baseURL: URL, chatID: String, date: Date) -> [URL] {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        let year = String(components.year ?? 1970)
        let month = String(format: "%02d", components.month ?? 1)
        let day = String(format: "%02d", components.day ?? 1)

        let yearURL = chatContainer(baseURL: baseURL, chatID: chatID).appendingPathComponent(year, isDirectory: true)
        let monthURL = yearURL.appendingPathComponent(month, isDirectory: true)
        let dayURL = monthURL.appendingPathComponent(day, isDirectory: true)
        return [yearURL, monthURL, dayURL]
    }

    static func messageResource(baseURL: URL, chatID: String, date: Date) -> URL {
        messageContainers(baseURL: baseURL, chatID: chatID, date: date)
            .last!
            .appendingPathComponent(LinxSharedContract.Resource.messagesFileName, isDirectory: false)
    }

    static func chatURI(baseURL: URL, chatID: String) -> String {
        chatIndexResource(baseURL: baseURL, chatID: chatID).absoluteString
            + "#\(LinxSharedContract.Resource.chatSubjectFragment)"
    }

    static func threadURI(baseURL: URL, chatID: String, threadID: String) -> String {
        chatIndexResource(baseURL: baseURL, chatID: chatID).absoluteString + "#\(threadID)"
    }

    static func agentURI(baseURL: URL, agentID: String) -> String {
        agentResource(baseURL: baseURL, agentID: agentID).absoluteString
    }

    static func messageSubjectURI(baseURL: URL, chatID: String, messageID: String, date: Date) -> String {
        messageResource(baseURL: baseURL, chatID: chatID, date: date).absoluteString + "#\(messageID)"
    }

    static func fragmentID(from uri: String) -> String {
        if let fragment = URL(string: uri)?.fragment, !fragment.isEmpty {
            return fragment
        }
        return uri.components(separatedBy: "#").last ?? uri
    }
}
