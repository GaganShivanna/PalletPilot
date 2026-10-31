import Foundation

/// Connectivity probe against the verified `GET /health` route.
/// ViewModels depend on the protocol, never on URLSession.
protocol HealthServiceProtocol: Sendable {
    func checkHealth() async throws -> HealthResponse
}

struct HealthService: HealthServiceProtocol {
    let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func checkHealth() async throws -> HealthResponse {
        try await client.get("/health", as: HealthResponse.self)
    }
}
