import SwiftUI

/// Pallet summary screen (screenshot 7): hero profit card, money breakdown,
/// attention rows, and top items. Values come from `PalletSummary` verbatim.
/// Note: the design's "manifest item not seen" row has no backend endpoint
/// and is intentionally omitted (see deliverables).
struct SummaryView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: SummaryViewModel

    init(viewModel: SummaryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(viewModel.palletName) · \(viewModel.itemCount) items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    switch viewModel.state {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding()
                    case .failed(let message):
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                    case .loaded:
                        heroCard
                        SectionHeader(text: "How we got there")
                        breakdownCard
                        Text("Fees and prices are estimates. Unpriced items are not counted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        SectionHeader(text: "Needs attention")
                        attentionCard
                        Text("Not seen in the video doesn't mean missing. Check the pallet first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        SectionHeader(text: "Top items")
                        topItemsCard
                        PrimaryButton(title: "Export CSV") {
                            router.navigate(to: .export(palletId: viewModel.palletId))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projected profit")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(AppTheme.price(viewModel.summary?.projectedProfit))
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(AppTheme.profit)
            if let summary = viewModel.summary {
                Text("Estimate · \(summary.pallet.pricedItemCount) of \(summary.pallet.itemCount) items priced")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            breakdownRow(label: "Estimated resale", value: AppTheme.price(viewModel.summary?.estimatedRevenue))
            Divider().padding(.leading, 16)
            breakdownRow(label: "Selling fees (\(viewModel.feeRatePercent)%)", value: "−\(AppTheme.price(viewModel.summary?.estimatedFees))")
            Divider().padding(.leading, 16)
            if let summary = viewModel.summary {
                breakdownRow(label: "Purchase cost", value: "−\(AppTheme.price(summary.pallet.purchaseCost))")
                Divider().padding(.leading, 16)
                breakdownRow(label: "Additional costs", value: "−\(AppTheme.price(summary.pallet.additionalCosts))")
                Divider().padding(.leading, 16)
            }
            HStack {
                Text("Projected profit").font(.headline)
                Spacer()
                Text(AppTheme.price(viewModel.summary?.projectedProfit))
                    .font(.headline)
                    .foregroundStyle(AppTheme.profit)
            }
            .padding(12)
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private func breakdownRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            Text(value).font(.body)
        }
        .padding(12)
    }

    private var attentionCard: some View {
        VStack(spacing: 0) {
            Button {
                router.navigate(to: .inventory(palletId: viewModel.palletId))
            } label: {
                HStack {
                    Text("\(viewModel.summary?.unpricedItemCount ?? 0) items without a price")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Review")
                        .font(.body)
                        .foregroundStyle(AppTheme.primary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(12)
            }
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var topItemsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.topItems.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    Text(AppTheme.price(item.suggestedPrice))
                        .font(.body.weight(.semibold))
                }
                .padding(12)
                if index < viewModel.topItems.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }
}
