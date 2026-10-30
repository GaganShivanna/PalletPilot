import SwiftUI

/// Foundation Home screen: app identity plus a backend connectivity check
/// against the verified `GET /health` route. No inventory, upload, or pricing
/// UI lives here (Phase 1 scope).
struct HomeView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("PalletPilot")
                .font(.largeTitle.bold())
            Text("Liquidation pallet resale")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ConnectionStatusView(
                state: viewModel.connection,
                baseURL: viewModel.baseURLDescription
            ) {
                Task { await viewModel.checkConnection() }
            }

            Button {
                router.navigate(to: .upload)
            } label: {
                Label("New pallet from video", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("Home")
    }
}

