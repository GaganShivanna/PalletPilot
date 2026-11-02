import SwiftUI

/// Inventory screen (screenshot 5): grouped list of pallet items with
/// review/price filters, status + needs-review banners, and Summary / Export
/// handoffs. Data comes from `GET /pallets/{id}/items` + `GET /pallets/{id}`;
/// `Job.listings` is never read here (stale-after-edit rule).
struct InventoryView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: InventoryViewModel

    init(viewModel: InventoryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.groupedBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    switch viewModel.state {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding()
                    case .failed(let message):
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                    case .loaded:
                        if viewModel.isStillProcessing {
                            processingCard
                        }
                        if viewModel.needsReviewCount > 0 {
                            NeedsReviewBanner(count: viewModel.needsReviewCount)
                                .padding(.horizontal, 16)
                        }
                        filterBar
                        SectionHeader(text: "Found so far")
                        itemCard
                        Text("Prices are estimates from recent sold listings. Tap an item to check it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 96)
                    }
                }
                .padding(.top, 8)
            }
            bottomBar
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.palletName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            + Text(" · \(viewModel.items.count) items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var processingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading) {
                Text("Identifying items · \(viewModel.items.count) of \(viewModel.summary?.pallet.itemCount ?? viewModel.items.count)")
                    .font(.headline)
                Text("New items appear here as they are found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    /// Custom filter bar: the system segmented picker clips the three
    /// count-bearing labels, so each segment scales its own text instead.
    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(InventoryFilter.allCases, id: \.self) { filter in
                let selected = viewModel.filter == filter
                Button {
                    viewModel.filter = filter
                } label: {
                    Text(viewModel.filterTitle(filter))
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selected ? Color(.systemBackground) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 16)
    }

    private var itemCard: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.filteredItems) { item in
                Button {
                    router.navigate(to: .itemDetail(itemId: item.id, palletId: viewModel.palletId))
                } label: {
                    InventoryRow(item: item)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item.id != viewModel.filteredItems.last?.id {
                    Divider().padding(.leading, 84)
                }
            }
        }
        .padding(.vertical, 4)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                router.navigate(to: .summary(palletId: viewModel.palletId))
            } label: {
                Text("Summary")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius))
            }
            Button {
                router.navigate(to: .export(palletId: viewModel.palletId))
            } label: {
                Text("Export CSV")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
