import SwiftUI

/// Item detail screen (screenshot 6): photo tabs, confidence + evidence line,
/// listing / condition / price / description groups, and a review toggle.
/// Edits persist via `PATCH /items/{id}`; Save sits in the toolbar.
struct ItemDetailView: View {
    @StateObject private var viewModel: ItemDetailViewModel

    init(viewModel: ItemDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statusBanner
                    photoTabs
                    photoCard
                    Text("The item is not redrawn, so buyers see its real condition.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    titleBlock
                    SectionHeader(text: "Listing")
                    listingCard
                    SectionHeader(text: "Condition")
                    conditionCard
                    Text("New, Like new, Good, Fair, Poor, For parts")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    SectionHeader(text: "Price")
                    priceCard
                        .onChange(of: viewModel.priceText) { viewModel.clearPriceError() }
                    if let priceError = viewModel.priceError {
                        Text(priceError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }
                    if case .loaded = viewModel.state {
                        Text(viewModel.priceFootnote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    SectionHeader(text: "Description")
                    descriptionCard
                    reviewCard
                    Text("Your edits are saved as corrections and update the pallet totals.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await viewModel.save() } }
                    .disabled(!viewModel.canSave)
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch viewModel.state {
        case .loading:
            HStack {
                ProgressView()
                Text("Loading item…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        case .saving:
            HStack {
                ProgressView()
                Text("Saving…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if viewModel.item == nil {
                    Button("Retry") { Task { await viewModel.load() } }
                        .buttonStyle(.bordered)
                } else {
                    Button("Try saving again") { Task { await viewModel.save() } }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)
        case .loaded:
            EmptyView()
        }
    }

    private var photoTabs: some View {
        Picker("Photo", selection: $viewModel.photoTab) {
            ForEach(ItemPhotoTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private var photoCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.box")
                .font(.system(size: 56))
                .foregroundStyle(Color(.systemGray2))
            Text(viewModel.photoTab == .clean ? "Muse Image · background cleaned" : "Original camera frame")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.item?.title ?? viewModel.title)
                .font(.title2.bold())
            HStack(spacing: 8) {
                if let percent = viewModel.confidencePercent {
                    ConfidenceBadge(text: "\(percent)% sure")
                }
                Text(viewModel.evidenceLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    private var listingCard: some View {
        VStack(spacing: 0) {
            listingField(label: "Title", value: $viewModel.title, axis: .vertical)
            Divider().padding(.leading, 16)
            listingField(label: "Brand", value: $viewModel.brand)
            Divider().padding(.leading, 16)
            listingField(label: "Category", value: $viewModel.category)
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private func listingField(label: String, value: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(label, text: value, axis: axis)
                .font(.body)
        }
        .padding(12)
    }

    private var conditionCard: some View {
        HStack {
            Text("Condition").font(.body)
            Spacer()
            Picker("Condition", selection: $viewModel.condition) {
                ForEach(ItemCondition.allCases, id: \.self) { condition in
                    Text(AppTheme.conditionLabel(condition.rawValue)).tag(condition)
                }
            }
            .tint(AppTheme.primary)
            Image(systemName: "chevron.right")
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(12)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var priceCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Suggested price").font(.body)
                Spacer()
                TextField("0", text: $viewModel.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 120)
            }
            .padding(12)
            Divider().padding(.leading, 16)
            HStack {
                Text("Source").font(.body)
                Spacer()
                Text(viewModel.priceSourceLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider().padding(.leading, 16)
            HStack {
                Text("Price confidence").font(.body)
                Spacer()
                Text(viewModel.priceConfidenceLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var descriptionCard: some View {
        TextEditor(text: $viewModel.descriptionText)
            .font(.body)
            .frame(minHeight: 120)
            .padding(8)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .padding(.horizontal, 16)
    }

    private var reviewCard: some View {
        HStack {
            Text("Mark as reviewed").font(.body)
            Spacer()
            Toggle("", isOn: $viewModel.markReviewed)
                .labelsHidden()
        }
        .padding(12)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }
}
