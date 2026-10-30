import Foundation

/// Pallet creation body. All fields optional server-side
/// (`backend/app/schemas/pallets.py: PalletCreate`).
struct PalletCreate: Codable, Sendable, Equatable {
    var name: String
    var purchaseCost: Double
    var additionalCosts: Double
    var jobId: String?

    init(name: String = "Untitled pallet", purchaseCost: Double = 0.0,
         additionalCosts: Double = 0.0, jobId: String? = nil) {
        self.name = name
        self.purchaseCost = purchaseCost
        self.additionalCosts = additionalCosts
        self.jobId = jobId
    }
}

/// `POST /pallets` response and the `pallet` member of `PalletSummary`.
/// `status` and counts are server-derived (`backend/app/routes/pallets.py`).
struct Pallet: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var purchaseCost: Double
    var additionalCosts: Double
    var jobId: String?
    /// Derived: `empty | processing | ready | failed`. Never sent by the client.
    var status: String
    var itemCount: Int
    var pricedItemCount: Int
    var createdAt: Date?
    var updatedAt: Date?
}

/// `GET /pallets/{pallet_id}` response. All money is an estimate
/// (`estimates: true`); unpriced items are excluded from revenue, never $0
/// (`backend/app/services/financials.py`).
struct PalletSummary: Codable, Sendable, Equatable {
    var pallet: Pallet
    var estimatedRevenue: Double?
    var estimatedFees: Double?
    var projectedProfit: Double?
    var feeRate: Double
    var unpricedItemCount: Int
    var estimates: Bool
}
