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
    @Published private(set) var recentPallets: [PalletHistoryEntry] = []
    @Published private(set) var recentStatuses: [String: String] = [:]

    private let healthService: HealthServiceProtocol
    private let historyStore: PalletHistoryStore
    private let palletService: PalletServiceProtocol?

    init(
        healthService: HealthServiceProtocol,
        baseURLDescription: String,
        historyStore: PalletHistoryStore = .init(),
        palletService: PalletServiceProtocol? = nil
    ) {
        self.healthService = healthService
        self.baseURLDescription = baseURLDescription
        self.historyStore = historyStore
        self.palletService = palletService
    }

    convenience init(container: AppContainer) {
        self.init(
            healthService: container.healthService,
            baseURLDescription: container.configuration.baseURL.absoluteString,
            historyStore: container.palletHistoryStore,
            palletService: container.palletService
        )
    }

    func refreshRecents() {
        recentPallets = historyStore.recents()
        guard let palletService else { return }
        Task { @MainActor in
            var statuses: [String: String] = [:]
            for entry in recentPallets {
                if let summary = try? await palletService.getSummary(palletId: entry.palletId) {
                    statuses[entry.palletId] = summary.pallet.status
                }
            }
            recentStatuses = statuses
        }
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
