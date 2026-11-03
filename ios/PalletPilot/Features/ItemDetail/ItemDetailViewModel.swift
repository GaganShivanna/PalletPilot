import Foundation

/// Item detail/edit state (`GET /items/{id}` then `PATCH /items/{id}` with the
/// 7 editable keys). Photo switching is display-only: there is no
/// image-management endpoint (INTEGRATION_GAPS.md G4).
enum ItemDetailLoadState: Equatable {
    case loading
    case loaded
    case saving
    case failed(message: String)
}

enum ItemPhotoTab: String, CaseIterable {
    case clean
    case original

    var title: String {
        switch self {
        case .clean: return "Clean photo"
        case .original: return "Original frame"
        }
    }
}

@MainActor
final class ItemDetailViewModel: ObservableObject {
    @Published private(set) var item: Item?
    @Published private(set) var state: ItemDetailLoadState = .loading
    @Published var photoTab: ItemPhotoTab = .clean

    // Editable copies (bound to the form).
    @Published var title = ""
    @Published var brand = ""
    @Published var category = ""
    @Published var descriptionText = ""
    @Published var condition: ItemCondition = .unknown
    @Published var priceText = ""
    @Published var markReviewed = false
    @Published var priceError: String?

    let itemId: String
    private let itemService: ItemServiceProtocol

    init(itemId: String, itemService: ItemServiceProtocol) {
        self.itemId = itemId
        self.itemService = itemService
    }

    convenience init(itemId: String, container: AppContainer) {
        self.init(itemId: itemId, itemService: container.itemService)
    }

    /// First review reason, falling back to the category: the only
    /// item-specific evidence the API provides (no verified market comps).
    var evidenceLine: String {
        if let reason = item?.reviewReasons.first, !reason.isEmpty { return reason }
        return item?.category ?? "Uncategorized"
    }

    /// Server price provenance (`price_source` / `price_type`); never claims
    /// a verified marketplace comparison the AI pipeline does not provide.
    var priceSourceLabel: String {
        guard let source = item?.priceSource, source != "none" else { return "No price source" }
        let type = item?.priceType ?? "unknown"
        return type == "unknown" ? "Estimate · \(source)" : "Estimate · \(source) · \(type)"
    }

    var priceConfidenceLabel: String {
        guard let confidence = item?.priceConfidence else { return "Unknown" }
        if confidence < 0.34 { return "Low" }
        if confidence < 0.67 { return "Medium" }
        return "High"
    }

    var priceFootnote: String {
        if item?.suggestedPrice == nil {
            return "No price estimate yet — unpriced items are not counted."
        }
        return "Estimates only, not verified market comps. Check before posting."
    }

    var canSave: Bool {
        if case .loading = state { return false }
        if case .saving = state { return false }
        return item != nil
    }

    var confidencePercent: Int? {
        guard let confidence = item?.confidence else { return nil }
        return Int((confidence * 100).rounded())
    }

    func clearPriceError() {
        priceError = nil
    }

    func load() async {
        state = .loading
        priceError = nil
        do {
            let item = try await itemService.getItem(id: itemId)
            apply(item)
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    func save() async {
        guard let item else { return }
        priceError = nil
        let trimmedPrice = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
        var newPrice: Double?
        var clearPrice = false
        if !trimmedPrice.isEmpty {
            guard let parsed = Double(trimmedPrice), parsed >= 0 else {
                priceError = "Enter a valid price of 0 or more."
                return
            }
            newPrice = parsed
        } else if item.suggestedPrice != nil {
            clearPrice = true
        }
        state = .saving
        do {
            var patch = ItemPatch()
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle != item.title { patch.title = trimmedTitle }
            let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedDescription != item.description { patch.description = trimmedDescription }
            let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCategory != item.category { patch.category = trimmedCategory }
            let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalBrand = item.brand ?? ""
            if trimmedBrand != originalBrand {
                patch.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            }
            if condition.rawValue != item.condition {
                patch.condition = condition
            }
            if clearPrice {
                patch.clearsPrice = true
            } else if let price = newPrice, price != item.suggestedPrice ?? -1 {
                patch.suggestedPrice = price
            }
            // Toggle semantics: on = approved (`needs_review: false`).
            let desiredNeedsReview = !markReviewed
            if desiredNeedsReview != item.needsReview {
                patch.needsReview = desiredNeedsReview
            }
            let updated = try await itemService.patchItem(id: itemId, patch: patch)
            apply(updated)
            state = .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    private func apply(_ item: Item) {
        self.item = item
        title = item.title
        brand = item.brand ?? ""
        category = item.category
        descriptionText = item.description
        condition = ItemCondition(rawValue: item.condition) ?? .unknown
        if let price = item.suggestedPrice {
            priceText = price.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(price)) : String(price)
        } else {
            priceText = ""
        }
        markReviewed = !item.needsReview
    }
}
