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

    let itemId: String
    private let itemService: ItemServiceProtocol

    init(itemId: String, itemService: ItemServiceProtocol) {
        self.itemId = itemId
        self.itemService = itemService
    }

    convenience init(itemId: String, container: AppContainer) {
        self.init(itemId: itemId, itemService: container.itemService)
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

    func load() async {
        state = .loading
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
            let trimmedPrice = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "$", with: "")
            if trimmedPrice.isEmpty {
                if item.suggestedPrice != nil { patch.clearsPrice = true }
            } else if let price = Double(trimmedPrice), price != item.suggestedPrice ?? -1 {
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
