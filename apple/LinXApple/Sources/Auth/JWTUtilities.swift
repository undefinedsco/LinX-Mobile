import Foundation

enum JWTUtilities {
    static func extractWebID(fromIDToken idToken: String) throws -> String {
        let payload = try decodePayload(from: idToken)

        if let webID = payload["webid"] as? String, URL(string: webID) != nil {
            return webID
        }

        if let subject = payload["sub"] as? String, URL(string: subject) != nil {
            return subject
        }

        throw LinxAppError.invalidIDToken
    }

    static func decodePayload(from token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { throw LinxAppError.invalidIDToken }

        let payloadPart = String(parts[1])
        let normalized = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = (4 - normalized.count % 4) % 4
        let padded = normalized + String(repeating: "=", count: paddingLength)

        guard let data = Data(base64Encoded: padded) else {
            throw LinxAppError.invalidIDToken
        }

        let json = try JSONSerialization.jsonObject(with: data)
        guard let payload = json as? [String: Any] else {
            throw LinxAppError.invalidIDToken
        }

        return payload
    }
}
