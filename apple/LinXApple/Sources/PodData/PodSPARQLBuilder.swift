import Foundation

enum PodSPARQLBuilder {
    private static let prefixes = """
    PREFIX dcterms: <http://purl.org/dc/terms/>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    PREFIX meeting: <http://www.w3.org/ns/pim/meeting#>
    PREFIX schema: <https://schema.org/>
    PREFIX sioc: <http://rdfs.org/sioc/ns#>
    PREFIX udfs: <https://undefineds.co/ns#>
    PREFIX wf: <http://www.w3.org/2005/01/wf/flow#>
    PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
    """

    static func escapeLiteral(_ value: String) -> String {
        if value.contains("\n") || value.contains("\r") || value.contains("\"") {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
            return "\"\"\"\(escaped)\"\"\""
        }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func dateLiteral(_ date: Date) -> String {
        "\"\(LinxDate.string(from: date))\"^^xsd:dateTime"
    }

    static func chatResourceTurtle(chatURI: String, createdAt: Date) -> String {
        """
        \(prefixes)

        <\(chatURI)> a meeting:LongChat ;
          dcterms:title \(escapeLiteral(AppConstants.defaultChatTitle)) ;
          dcterms:created \(dateLiteral(createdAt)) ;
          dcterms:modified \(dateLiteral(createdAt)) ;
          udfs:lastActiveAt \(dateLiteral(createdAt)) .
        """
    }

    static func agentResourceTurtle(agentURI: String, modelID: String, createdAt: Date) -> String {
        """
        \(prefixes)

        <\(agentURI)> a foaf:Agent ;
          foaf:name \(escapeLiteral(AppConstants.defaultAgentName)) ;
          udfs:provider \(escapeLiteral("xpod")) ;
          udfs:model \(escapeLiteral(modelID)) ;
          dcterms:created \(dateLiteral(createdAt)) ;
          dcterms:modified \(dateLiteral(createdAt)) .
        """
    }

    static func ensureEmptyTurtleResource() -> String {
        "# LinX message store\n"
    }

    static func threadsQuery(chatURI: String, limit: Int) -> String {
        """
        \(prefixes)

        SELECT ?thread ?title ?createdAt ?updatedAt
        WHERE {
          ?thread a sioc:Thread ;
                  sioc:has_parent <\(chatURI)> ;
                  dcterms:created ?createdAt .
          OPTIONAL { ?thread dcterms:title ?title . }
          OPTIONAL { ?thread dcterms:modified ?updatedAt . }
        }
        ORDER BY DESC(COALESCE(?updatedAt, ?createdAt))
        LIMIT \(limit)
        """
    }

    static func messagesQuery(threadURI: String, limit: Int, offset: Int) -> String {
        """
        \(prefixes)

        SELECT ?message ?maker ?role ?content ?richContent ?status ?createdAt ?updatedAt
        WHERE {
          <\(threadURI)> sioc:has_member ?message .
          ?message a meeting:Message ;
                   foaf:maker ?maker ;
                   udfs:messageType ?role ;
                   sioc:content ?content ;
                   dcterms:created ?createdAt .
          OPTIONAL { ?message sioc:richContent ?richContent . }
          OPTIONAL { ?message udfs:messageStatus ?status . }
          OPTIONAL { ?message dcterms:modified ?updatedAt . }
        }
        ORDER BY DESC(?createdAt)
        LIMIT \(limit)
        OFFSET \(offset)
        """
    }

    static func createThreadPatch(
        chatURI: String,
        threadURI: String,
        title: String,
        createdAt: Date
    ) -> String {
        """
        \(prefixes)

        INSERT DATA {
          <\(threadURI)> a sioc:Thread ;
            sioc:has_parent <\(chatURI)> ;
            dcterms:title \(escapeLiteral(title)) ;
            dcterms:created \(dateLiteral(createdAt)) ;
            dcterms:modified \(dateLiteral(createdAt)) .
        }
        """
    }

    static func insertMessagePatch(
        chatURI: String,
        threadURI: String,
        messageURI: String,
        makerURI: String,
        role: LinxMessageRole,
        content: String,
        status: LinxMessageStatus,
        createdAt: Date,
        richContent: String? = nil
    ) -> String {
        var richContentTriple = ""
        if let richContent {
            richContentTriple = "\n          sioc:richContent \(escapeLiteral(richContent)) ;"
        }

        return """
        \(prefixes)

        INSERT DATA {
          <\(chatURI)> wf:message <\(messageURI)> .
          <\(threadURI)> sioc:has_member <\(messageURI)> .
          <\(messageURI)> a meeting:Message ;
            foaf:maker <\(makerURI)> ;
            udfs:messageType \(escapeLiteral(role.rawValue)) ;
            sioc:content \(escapeLiteral(content)) ;\(richContentTriple)
            udfs:messageStatus \(escapeLiteral(status.rawValue)) ;
            dcterms:created \(dateLiteral(createdAt)) ;
            dcterms:modified \(dateLiteral(createdAt)) .
        }
        """
    }

    static func patchMessageContent(
        messageURI: String,
        content: String,
        richContent: String?,
        status: LinxMessageStatus,
        updatedAt: Date
    ) -> String {
        var insertTriples = [
            "<\(messageURI)> sioc:content \(escapeLiteral(content)) .",
            "<\(messageURI)> udfs:messageStatus \(escapeLiteral(status.rawValue)) .",
            "<\(messageURI)> dcterms:modified \(dateLiteral(updatedAt)) .",
        ]

        if let richContent {
            insertTriples.append("<\(messageURI)> sioc:richContent \(escapeLiteral(richContent)) .")
        }

        return """
        \(prefixes)

        DELETE {
          <\(messageURI)> sioc:content ?oldContent .
          <\(messageURI)> sioc:richContent ?oldRichContent .
          <\(messageURI)> udfs:messageStatus ?oldStatus .
          <\(messageURI)> dcterms:modified ?oldUpdatedAt .
        }
        INSERT {
          \(insertTriples.joined(separator: "\n          "))
        }
        WHERE {
          OPTIONAL { <\(messageURI)> sioc:content ?oldContent . }
          OPTIONAL { <\(messageURI)> sioc:richContent ?oldRichContent . }
          OPTIONAL { <\(messageURI)> udfs:messageStatus ?oldStatus . }
          OPTIONAL { <\(messageURI)> dcterms:modified ?oldUpdatedAt . }
        }
        """
    }

    static func patchActivity(
        chatURI: String,
        threadURI: String,
        preview: String,
        updatedAt: Date
    ) -> String {
        """
        \(prefixes)

        DELETE {
          <\(chatURI)> schema:text ?oldPreview .
          <\(chatURI)> udfs:lastActiveAt ?oldLastActiveAt .
          <\(chatURI)> dcterms:modified ?oldChatUpdatedAt .
          <\(threadURI)> dcterms:modified ?oldThreadUpdatedAt .
        }
        INSERT {
          <\(chatURI)> schema:text \(escapeLiteral(preview)) .
          <\(chatURI)> udfs:lastActiveAt \(dateLiteral(updatedAt)) .
          <\(chatURI)> dcterms:modified \(dateLiteral(updatedAt)) .
          <\(threadURI)> dcterms:modified \(dateLiteral(updatedAt)) .
        }
        WHERE {
          OPTIONAL { <\(chatURI)> schema:text ?oldPreview . }
          OPTIONAL { <\(chatURI)> udfs:lastActiveAt ?oldLastActiveAt . }
          OPTIONAL { <\(chatURI)> dcterms:modified ?oldChatUpdatedAt . }
          OPTIONAL { <\(threadURI)> dcterms:modified ?oldThreadUpdatedAt . }
        }
        """
    }
}
