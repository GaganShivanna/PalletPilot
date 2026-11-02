import Foundation

/// Inventory list state for one pallet (`GET /pallets/{id}/items` +
/// `GET /pallets/{id}` header). Filtering is client-side (no filter params
/// exist server-side — INTEGRATION_GAPS.md G6).
enum InventoryLoadState: Equatable {
    case loading
    case loaded
    case failed(message: String)
}

enum InventoryFilter: String, CaseIterable {
    case all
    case needsReview
    case noPrice
}

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var summary: PalletSummary?
    @Published private(set) var state: InventoryLoadState = .loading
    @Published var filter: InventoryFilter = .all

    let palletId: String
    private let palletService: PalletServiceProtocol

    init(palletId: String, palletService: PalletServiceProtocol) {
        self.palletId = palletId
        self.palletService = palletService
    }

    convenience init(palletId: String, container: AppContainer) {
        self.init(palletId: palletId, palletService: container.palletService)
    }

    var palletName: String { summary?.pallet.name ?? "Pallet" }

    var needsReviewCount: Int { items.filter(\.needsReview).count }
    var noPriceCount: Int { items.filter { $0.suggestedPrice == nil }.count }

    var filteredItems: [Item] {
        switch filter {
        case .all: return items
        case .needsReview: return items.filter(\.needsReview)
        case .noPrice: return items.filter { $0.suggestedPrice == nil }
        }
    }

    var isStillProcessing: Bool {
        summary.map { $0.pallet.status == "processing" } ?? false
    }

    func filterTitle(_ filter: InventoryFilter) -> String {
        switch filter {
        case .all: return "All \(items.count)"
        case .needsReview: return "Needs review \(needsReviewCount)"
        case .noPrice: return "No price \(noPriceCount)"
        }
    }

    func load() async {
        state = .loading
        do {
            async let itemsCall = palletService.listItems(palletId: palletId)
            async let summaryCall = palletService.getSummary(palletId: palletId)
            let (items, summary) = try await (itemsCall, summaryCall)
            self.items = items
            self.summary = summary
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}
