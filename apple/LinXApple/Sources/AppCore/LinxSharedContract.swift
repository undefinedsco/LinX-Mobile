import Foundation

enum LinxSharedContract {
    enum Defaults {
        static let appName = "LinX Apple"
        static let bundleIdentifier = "co.undefineds.linx.apple"
        static let defaultModelID = "linx-lite"
        static let fallbackModelIDs = ["linx", defaultModelID]
        static let defaultChatID = "ios-default"
        static let defaultAgentID = "linx-ios-assistant"
        static let defaultChatTitle = "LinX iOS"
        static let defaultAgentName = "LinX iOS Assistant"
        static let defaultThreadTitle = "iOS Session"
        static let defaultThreadWorkspace = "co.undefineds.linx.apple://workspace/default"
    }

    enum Runtime {
        static let identityOrigin = "https://id.undefineds.co"
        static let apiOrigin = "https://api.undefineds.co"
        static let apiVersion = "v1"
        static let identityHosts = ["id.undefineds.co"]

        static let issuerURL = URL(string: identityOrigin)!
        static let discoveryURL = URL(string: "\(identityOrigin)/.well-known/openid-configuration")!
        static let runtimeBaseURL = URL(string: apiOrigin)!

        static func resolveRuntimeOrigin(forIssuerURL issuerURL: URL) -> URL {
            LinxRuntimeTargetResolver.resolveRuntimeOrigin(forIssuerURL: issuerURL)
        }

        static func apiBaseURL(runtimeBaseURL: URL, version: String = apiVersion) -> URL {
            LinxRuntimeTargetResolver.apiBaseURL(runtimeBaseURL: runtimeBaseURL, version: version)
        }

        static func endpoint(runtimeBaseURL: URL, version: String = apiVersion, path: String) -> URL {
            LinxRuntimeTargetResolver.endpoint(runtimeBaseURL: runtimeBaseURL, version: version, path: path)
        }
    }

    enum Namespace {
        static let dcterms = "http://purl.org/dc/terms/"
        static let foaf = "http://xmlns.com/foaf/0.1/"
        static let meeting = "http://www.w3.org/ns/pim/meeting#"
        static let schema = "http://schema.org/"
        static let sioc = "http://rdfs.org/sioc/ns#"
        static let udfs = "https://undefineds.co/ns#"
        static let wf = "http://www.w3.org/2005/01/wf/flow-1.0#"
        static let xsd = "http://www.w3.org/2001/XMLSchema#"
    }

    enum RDFClass {
        static let longChat = Namespace.meeting + "LongChat"
        static let message = Namespace.meeting + "Message"
        static let thread = Namespace.sioc + "Thread"
        static let agent = Namespace.foaf + "Agent"
    }

    enum Predicate {
        static let title = Namespace.dcterms + "title"
        static let created = Namespace.dcterms + "created"
        static let modified = Namespace.dcterms + "modified"
        static let maker = Namespace.foaf + "maker"
        static let name = Namespace.foaf + "name"
        static let image = Namespace.schema + "image"
        static let text = Namespace.schema + "text"
        static let hasParent = Namespace.sioc + "has_parent"
        static let hasMember = Namespace.sioc + "has_member"
        static let content = Namespace.sioc + "content"
        static let richContent = Namespace.sioc + "richContent"
        static let message = Namespace.wf + "message"
        static let participant = Namespace.wf + "participant"
        static let lastActiveAt = Namespace.udfs + "lastActiveAt"
        static let provider = Namespace.udfs + "provider"
        static let model = Namespace.udfs + "model"
        static let messageType = Namespace.udfs + "messageType"
        static let messageStatus = Namespace.udfs + "messageStatus"
        static let workspace = Namespace.udfs + "workspace"
    }

    enum Resource {
        static let dataContainerName = ".data"
        static let chatContainerName = "chat"
        static let agentsContainerName = "agents"
        static let chatIndexFileName = "index.ttl"
        static let agentFileExtension = "ttl"
        static let messagesFileName = "messages.ttl"
        static let chatSubjectFragment = "this"

        enum SubjectTemplate {
            static let chat = "{id}/index.ttl#this"
            static let thread = "{chat|id}/index.ttl#{id}"
            static let message = "{chat|id}/{yyyy}/{MM}/{dd}/messages.ttl#{id}"
            static let agent = "{id}.ttl"
        }
    }

    static func preferredModelID(from models: [RuntimeModelSummary]) -> String {
        let ids = models.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ids.first { $0 == Defaults.defaultModelID } ?? ids.first ?? Defaults.defaultModelID
    }
}
