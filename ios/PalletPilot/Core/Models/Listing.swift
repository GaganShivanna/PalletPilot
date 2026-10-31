import Foundation

/// One listing draft embedded in a `Job` (`backend/app/schemas/listings.py`).
struct Listing: Codable, Sendable, Equatable, Identifiable {
    /// Backend key is `item_id`.
    var itemId: String
    var id: String { itemId }
    var title: String
    var description: String
    var category: String
    var brand: String?
    var condition: String
    var price: Price
    /// Relative paths served by `GET /jobs/{job_id}/files/{path}`.
    var imageUrls: [String]
    var confidence: Double?
    var needsReview: Bool
    var reviewReasons: [String]
}

struct Price: Codable, Sendable, Equatable {
    var amount: Double?
    var currency: String
}
