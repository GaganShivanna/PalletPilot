import SwiftUI

/// Filled blue action button used by Inventory / Summary / Export.
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? AppTheme.primary : Color(.systemGray4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonRadius))
        }
        .disabled(!enabled)
    }
}

/// Gray rounded thumbnail with a cube placeholder (real photos arrive via
/// `GET /jobs/{id}/files/...`; mock jobs have no loadable bytes in previews).
struct ItemThumbnail: View {
    var size: CGFloat = AppTheme.rowThumbnail

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "cube.box")
                    .font(.title2)
                    .foregroundStyle(Color(.systemGray2))
            )
    }
}

/// Server-backed item photo with the cube placeholder while loading or when
/// `url` is nil. `url` must be an absolute files-endpoint URL.
struct ItemPhotoImage: View {
    let url: URL?
    var size: CGFloat = AppTheme.rowThumbnail

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        ItemThumbnail(size: size)
                    case .empty:
                        ItemThumbnail(size: size)
                            .overlay { ProgressView() }
                    @unknown default:
                        ItemThumbnail(size: size)
                    }
                }
            } else {
                ItemThumbnail(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Orange rounded-rect badge for per-row `review_reasons` (first reason shown).
struct ReviewBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.warningText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppTheme.reviewPillBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Green confidence badge (`91% sure`).
struct ConfidenceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.confidencePillText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppTheme.confidencePillBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Uppercase grouped-list section header.
struct SectionHeader: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.subheadline)
            .foregroundStyle(AppTheme.sectionHeader)
            .padding(.horizontal, 20)
    }
}

/// One tappable inventory row matching screenshot 5.
struct InventoryRow: View {
    let item: Item
    /// Absolute files-endpoint URL for the row photo; nil keeps the placeholder.
    var imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            ItemPhotoImage(url: imageURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if item.needsReview, let reason = item.reviewReasons.first {
                    ReviewBadge(text: reason)
                }
            }
            Spacer()
            if let price = item.suggestedPrice {
                Text(AppTheme.price(price))
                    .font(.title3.weight(.semibold))
            } else {
                Text("No price")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 8)
    }
}

/// Amber banner for `N items need review before export`.
struct NeedsReviewBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
            Text("\(count) items need review before export")
                .font(.headline)
        }
        .foregroundStyle(AppTheme.warningText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.warningBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
