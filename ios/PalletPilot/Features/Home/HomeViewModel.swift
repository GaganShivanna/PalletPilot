import Foundation

/// Connection states for the Home connectivity check (`GET /health`).
enum ConnectionState: Equatable {
    case idle
    case checking
    case connected(serverStatus: String)
    case failed(message: String)
}

/// Home screen state. Owns the backend connectivity check; rendering lives in
/// `HomeView`. Depends on `HealthServiceProtocol` so tests can inject fakes.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var connection: ConnectionState = .idle
    @Published private(set) var baseURLDescription: String

    private let healthService: HealthServiceProtocol

    init(healthService: HealthServiceProtocol, baseURLDescription: String) {
        self.healthService = healthService
        self.baseURLDescription = baseURLDescription
    }

    convenience init(container: AppContainer) {
        self.init(
            healthService: container.healthService,
            baseURLDescription: container.configuration.baseURL.absoluteString
        )
    }

    func checkConnection() async {
        connection = .checking
        do {
            let health = try await healthService.checkHealth()
            connection = health.isHealthy
                ? .connected(serverStatus: health.status)
                : .failed(message: "Unexpected status: \(health.status)")
        } catch {
            connection = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}
