import Foundation

/// Pallet summary state (`GET /pallets/{id}` + top items from
/// `GET /pallets/{id}/items`). All money is server-computed estimates —
/// the client never recomputes totals (INTEGRATION_GAPS.md G13).
enum SummaryLoadState: Equatable {
    case loading
    case loaded
    case failed(message: String)
}

@MainActor
final class SummaryViewModel: ObservableObject {
    @Published private(set) var summary: PalletSummary?
    @Published private(set) var topItems: [Item] = []
    @Published private(set) var state: SummaryLoadState = .loading

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
    var itemCount: Int { summary?.pallet.itemCount ?? topItems.count }
    var feeRatePercent: Int { Int(((summary?.feeRate ?? 0.13) * 100).rounded()) }

    func load() async {
        state = .loading
        do {
            async let summaryCall = palletService.getSummary(palletId: palletId)
            async let itemsCall = palletService.listItems(palletId: palletId)
            let (summary, items) = try await (summaryCall, itemsCall)
            self.summary = summary
            self.topItems = items
                .filter { $0.suggestedPrice != nil }
                .sorted { ($0.suggestedPrice ?? 0) > ($1.suggestedPrice ?? 0) }
                .prefix(3)
                .map { $0 }
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}
