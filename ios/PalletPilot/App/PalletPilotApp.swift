import SwiftUI

@main
struct PalletPilotApp: App {
    @StateObject private var router = AppRouter()
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $router.path) {
                HomeView(viewModel: HomeViewModel(container: container))
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .home:
                            HomeView(viewModel: HomeViewModel(container: container))
                        case .upload:
                            UploadView(viewModel: UploadViewModel(container: container))
                        case .processing(let jobId, let palletId):
                            ProcessingView(
                                viewModel: ProcessingViewModel(container: container, jobId: jobId),
                                palletId: palletId
                            )
                        case .capture(let palletId):
                            CaptureView(viewModel: CaptureViewModel(container: container), palletId: palletId)
                        case .inventory(let palletId):
                            InventoryView(viewModel: InventoryViewModel(palletId: palletId, container: container))
                        case .itemDetail(let itemId, _):
                            ItemDetailView(viewModel: ItemDetailViewModel(itemId: itemId, container: container))
                        case .summary(let palletId):
                            SummaryView(viewModel: SummaryViewModel(palletId: palletId, container: container))
                        case .export(let palletId):
                            ExportView(viewModel: ExportViewModel(palletId: palletId, container: container))
                        }
                    }
            }
            .environmentObject(router)
            .environment(\.router, router)
            .environment(\.container, container)
        }
    }
}
