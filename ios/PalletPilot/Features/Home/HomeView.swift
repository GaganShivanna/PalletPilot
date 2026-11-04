import SwiftUI

/// Home landing screen: app identity, quick actions, backend connectivity,
/// and recent pallets with live server status. All content is live — the
/// pallet list comes from this device's history plus per-pallet status reads.
struct HomeView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: HomeViewModel
    @State private var appeared = false

    init(viewModel: HomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                        .entrance(index: 0, appeared: appeared)
                    actionsCard
                        .entrance(index: 1, appeared: appeared)
                    ConnectionStatusView(
                        state: viewModel.connection,
                        baseURL: viewModel.baseURLDescription
                    ) {
                        Task { await viewModel.checkConnection() }
                    }
                    .entrance(index: 2, appeared: appeared)
                    if !viewModel.recentPallets.isEmpty {
                        recentsCard
                            .entrance(index: 3, appeared: appeared)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Home")
        .onAppear {
            viewModel.refreshRecents()
            withAnimation { appeared = true }
        }
        .task { await viewModel.checkConnection() }
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primary.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "cube.box.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("PalletPilot")
                    .font(.title2.bold())
                Text("Liquidation pallet resale")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !viewModel.recentPallets.isEmpty {
                    Text(
                        "\(viewModel.recentPallets.count) recent pallet\(viewModel.recentPallets.count == 1 ? "" : "s") on this device"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var actionsCard: some View {
        VStack(spacing: 8) {
            Button {
                router.navigate(to: .upload)
            } label: {
                Label("New pallet from video", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            HStack(spacing: 8) {
                actionTile(title: "Open camera", systemImage: "camera.fill") {
                    router.navigate(to: .capture(palletId: nil, jobId: nil))
                }
                actionTile(title: "Past jobs", systemImage: "clock.arrow.circlepath") {
                    router.navigate(to: .history)
                }
            }
        }
    }

    private func actionTile(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var recentsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent pallets")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            ForEach(viewModel.recentPallets) { entry in
                Button {
                    router.navigate(to: .inventory(palletId: entry.palletId))
                } label: {
                    HStack {
                        Text(entry.name)
                            .lineLimit(1)
                        Spacer()
                        palletStatusBadge(for: entry.palletId)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if entry.id != viewModel.recentPallets.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
            .padding(.bottom, 8)
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    /// Server status pill for a recent pallet; empty while loading or offline.
    @ViewBuilder
    private func palletStatusBadge(for palletId: String) -> some View {
        if let status = viewModel.recentStatuses[palletId] {
            if status == "processing" {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            } else {
                Text(status.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(status))
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ready": return .green
        case "failed": return .red
        default: return .secondary
        }
    }
}

/// Staggered entrance for Home sections.
private struct EntranceModifier: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                .easeOut(duration: 0.4).delay(Double(index) * 0.08),
                value: appeared)
    }
}

private extension View {
    func entrance(index: Int, appeared: Bool) -> some View {
        modifier(EntranceModifier(index: index, appeared: appeared))
    }
}
