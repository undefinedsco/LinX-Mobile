import Foundation

enum LinxRuntimeTargetResolver {
    static func resolveRuntimeOrigin(forIssuerURL issuerURL: URL) -> URL {
        resolveRuntimeOrigin(
            forIssuerURL: issuerURL,
            cloudIdentityHosts: LinxSharedContract.Runtime.identityHosts,
            cloudRuntimeBaseURL: LinxSharedContract.Runtime.runtimeBaseURL
        )
    }

    static func resolveRuntimeOrigin(
        forIssuerURL issuerURL: URL,
        cloudIdentityHosts: [String],
        cloudRuntimeBaseURL: URL
    ) -> URL {
        if let host = issuerURL.host, cloudIdentityHosts.contains(host) {
            return normalizedURL(cloudRuntimeBaseURL)
        }

        return normalizedURL(issuerURL)
    }

    static func apiBaseURL(runtimeBaseURL: URL, version: String) -> URL {
        let trimmed = runtimeBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/\(version)") {
            return URL(string: trimmed)!
        }
        return URL(string: "\(trimmed)/\(version)")!
    }

    static func endpoint(runtimeBaseURL: URL, version: String, path: String) -> URL {
        path
            .split(separator: "/")
            .reduce(apiBaseURL(runtimeBaseURL: runtimeBaseURL, version: version)) { url, component in
                url.appendingPathComponent(String(component), isDirectory: false)
            }
    }

    private static func normalizedURL(_ url: URL) -> URL {
        let trimmed = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed) ?? url
    }
}
