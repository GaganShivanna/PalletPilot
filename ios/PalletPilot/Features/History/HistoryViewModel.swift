import Foundation

/// Job-history list state (`GET /jobs`, newest first). Rows deep-link into
/// the inventory only when this device knows the pallet for the job (see
/// `PalletHistoryStore`); otherwise they are status-only.
enum HistoryLoadState: Equatable {
    case loading
    case loaded
    case failed(message: String)
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var state: HistoryLoadState = .loading

    private let jobService: JobServiceProtocol
    private let historyStore: PalletHistoryStore

    init(jobService: JobServiceProtocol, historyStore: PalletHistoryStore = .init()) {
        self.jobService = jobService
        self.historyStore = historyStore
    }

    convenience init(container: AppContainer) {
        self.init(
            jobService: container.jobService,
            historyStore: container.palletHistoryStore)
    }

    /// Inventory destination for a job, if this device linked it to a pallet.
    func palletId(for jobId: String) -> String? {
        historyStore.palletId(forJobId: jobId)
    }

    func load() async {
        state = .loading
        do {
            jobs = try await jobService.listJobs()
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}
