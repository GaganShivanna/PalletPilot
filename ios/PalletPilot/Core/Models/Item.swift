import Foundation

/// Item condition vocabulary enforced by `PATCH /items/{id}`
/// (`backend/app/schemas/items.py: CONDITIONS`).
enum ItemCondition: String, Codable, Sendable, CaseIterable {
    case new
    case likeNew = "like_new"
    case good
    case fair
    case poor
    case parts
    case unknown
}

/// `GET /pallets/{pallet_id}/items` element and `GET /items/{item_id}` response
/// (`backend/app/schemas/items.py: Item`).
///
/// `condition` stays a free `String` on decode: the validated vocabulary
/// applies to PATCH requests, and unknown future values must not break reads.
/// `suggestedPrice == nil` means unknown — never $0.
struct Item: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var palletId: String?
    var jobId: String?
    var trackId: String?
    var title: String
    var description: String
    var category: String
    var brand: String?
    var condition: String
    var suggestedPrice: Double?
    var currency: String
    var priceSource: String
    var priceConfidence: Double?
    var priceType: String
    /// Relative paths served by `GET /jobs/{job_id}/files/{path}`.
    var originalImageUrl: String?
    var imageUrls: [String]
    var confidence: Double?
    var needsReview: Bool
    var reviewReasons: [String]
    var provider: String
    var createdAt: Date?
    var updatedAt: Date?
}

/// `PATCH /items/{item_id}` body (`backend/app/schemas/items.py: ItemPatch`).
/// Only the 7 editable keys. Nil fields are OMITTED from the JSON: the server
/// treats explicitly provided keys as the change set, and sending
/// `"title": null` would corrupt a non-null column. The one supported explicit
/// null is price-clearing via `clearsPrice`.
struct ItemPatch: Sendable, Equatable {
    var title: String?
    var description: String?
    var category: String?
    var brand: String?
    var condition: ItemCondition?
    var suggestedPrice: Double?
    var needsReview: Bool?
    /// When true, encodes `"suggested_price": null` (explicit-null price clear).
    var clearsPrice: Bool = false

    static var clearingPrice: ItemPatch {
        var patch = ItemPatch()
        patch.clearsPrice = true
        return patch
    }
}

extension ItemPatch: Encodable {
    enum CodingKeys: String, CodingKey {
        case title
        case description
        case category
        case brand
        case condition
        case suggestedPrice = "suggested_price"
        case needsReview = "needs_review"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(condition, forKey: .condition)
        if clearsPrice {
            try container.encodeNil(forKey: .suggestedPrice)
        } else {
            try container.encodeIfPresent(suggestedPrice, forKey: .suggestedPrice)
        }
        try container.encodeIfPresent(needsReview, forKey: .needsReview)
    }
}
