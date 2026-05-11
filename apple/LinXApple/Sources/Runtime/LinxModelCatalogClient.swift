import Foundation

@MainActor
struct LinxModelCatalogClient {
    let authController: AuthSessionController

    func preferredModelID() async throws -> String {
        let token = try await authController.accessToken()
        var request = URLRequest(url: AppConstants.runtimeBaseURL.appendingPathComponent("\(AppConstants.runtimeVersion)/models"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw LinxAppError.invalidRuntimeResponse
        }

        let decoded = try JSONDecoder().decode(RuntimeModelListResponse.self, from: data)
        return try Self.pickPreferredModelID(from: decoded.data)
    }

    nonisolated static func pickPreferredModelID(from models: [RuntimeModelSummary]) throws -> String {
        if models.contains(where: { $0.id == AppConstants.defaultModelID }) {
            return AppConstants.defaultModelID
        }
        guard let first = models.first else {
            throw LinxAppError.emptyModelCatalog
        }
        return first.id
    }
}
