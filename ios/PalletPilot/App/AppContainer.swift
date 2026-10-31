import Foundation

/// Composition root. Views resolve dependencies from here via the environment;
/// tests construct ViewModels with mock services directly.
struct AppContainer: Sendable {
    let configuration: APIConfiguration
    let apiClient: APIClientProtocol
    let healthService: HealthServiceProtocol
    let palletService: PalletServiceProtocol
    let jobService: JobServiceProtocol

    /// Live backend wiring.
    static func live(session: URLSession = .shared) -> AppContainer {
        let configuration = APIConfiguration.resolved()
        let client = APIClient(configuration: configuration, session: session)
        return AppContainer(
            configuration: configuration,
            apiClient: client,
            healthService: HealthService(client: client),
            palletService: PalletService(client: client),
            jobService: JobService(client: client)
        )
    }

    /// Preview/test wiring with a stubbed client.
    static func preview(client: APIClientProtocol) -> AppContainer {
        AppContainer(
            configuration: .simulatorDefault,
            apiClient: client,
            healthService: HealthService(client: client),
            palletService: PalletService(client: client),
            jobService: JobService(client: client)
        )
    }
}
