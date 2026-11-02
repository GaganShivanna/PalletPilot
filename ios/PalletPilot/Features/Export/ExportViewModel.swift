import Foundation

/// Export screen state. Counts come from `GET /pallets/{id}/items`; the CSV
/// bytes come from `GET /pallets/{id}/export` (server-generated, always the
/// full list — there is no include-unreviewed query param, so the toggle is a
/// local preference applied to the on-device copy note, not the request).
enum ExportLoadState: Equatable {
    case loading
    case loaded
    case failed(message: String)
}

@MainActor
final class ExportViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var state: ExportLoadState = .loading
    @Published var includeUnreviewed = false
    @Published private(set) var csvData: Data?
    @Published var shareError: String?

    let palletId: String
    private let palletService: PalletServiceProtocol

    init(palletId: String, palletService: PalletServiceProtocol) {
        self.palletId = palletId
        self.palletService = palletService
    }

    convenience init(palletId: String, container: AppContainer) {
        self.init(palletId: palletId, palletService: container.palletService)
    }

    var reviewedCount: Int { items.filter { !$0.needsReview }.count }
    var unreviewedCount: Int { items.filter(\.needsReview).count }
    /// Items without a price are donate/skip candidates (no delete endpoint).
    var donateCount: Int { items.filter { $0.suggestedPrice == nil }.count }

    var fileName: String { "pallet-export-\(palletId.prefix(8)).csv" }

    func load() async {
        state = .loading
        do {
            items = try await palletService.listItems(palletId: palletId)
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    func fetchCSV() async {
        shareError = nil
        do {
            csvData = try await palletService.exportCSV(palletId: palletId)
        } catch {
            shareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
