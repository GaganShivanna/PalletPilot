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
                        }
                    }
            }
            .environmentObject(router)
            .environment(\.router, router)
            .environment(\.container, container)
        }
    }
}
