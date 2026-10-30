import Foundation
import Testing
@testable import PalletPilot

/// Contract decoding tests (Swift Testing). Fixtures mirror backend shapes
/// from `backend/tests/test_phase2.py` and docs/ios/API_CONTRACTS.md.
@Suite("Backend contract decoding")
struct DecodingTests {
    private func decoder() -> JSONDecoder {
        // Same configuration as APIClient: snake_case + fractional ISO 8601.
        var decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO 8601 date: \(raw)")
        }
        return decoder
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    @Test("Health decodes")
    func health() throws {
        let health = try decode(HealthResponse.self, Fixtures.health)
        #expect(health == HealthResponse(status: "ok"))
        #expect(health.isHealthy)
    }

    @Test("Completed job with listings decodes")
    func jobCompleted() throws {
        let job = try decode(Job.self, Fixtures.jobCompleted)
        #expect(job.id == Fixtures.jobId)
        #expect(job.status == .completed)
        #expect(job.status.isTerminal)
        #expect(job.frameCount == 6)
        #expect(job.error == nil)
        #expect(job.listings.count == 1)
        let listing = try #require(job.listings.first)
        #expect(listing.itemId == "\(Fixtures.jobId):item_0")
        #expect(listing.price.amount == 45.0)
        #expect(listing.price.currency == "USD")
        #expect(listing.needsReview)
    }

    @Test("Job status enum covers the pipeline lifecycle")
    func jobStatusCases() throws {
        let raw = ["queued", "sampling_frames", "segmenting", "identifying",
                   "generating_photos", "generating_listings", "completed", "failed"]
        let decoded = try raw.map { try decode(JobStatus.self, "\"\($0)\"") }
        #expect(decoded == JobStatus.allCases)
        #expect(JobStatus.completed.isTerminal)
        #expect(JobStatus.failed.isTerminal)
        #expect(!JobStatus.identifying.isTerminal)
    }

    @Test("Pallet decodes with null job and dates")
    func pallet() throws {
        let pallet = try decode(Pallet.self, Fixtures.pallet)
        #expect(pallet.id == Fixtures.palletId)
        #expect(pallet.jobId == nil)
        #expect(pallet.status == "empty")
        #expect(pallet.createdAt != nil)
    }

    @Test("PalletSummary decodes estimates")
    func palletSummary() throws {
        let summary = try decode(PalletSummary.self, Fixtures.palletSummary)
        #expect(summary.pallet.status == "ready")
        #expect(summary.estimatedRevenue == 77.5)
        #expect(summary.projectedProfit == 42.43)
        #expect(summary.feeRate == 0.13)
        #expect(summary.unpricedItemCount == 1)
        #expect(summary.estimates)
    }

    @Test("Priced item decodes all fields")
    func itemPriced() throws {
        let item = try decode(Item.self, Fixtures.itemPriced)
        #expect(item.suggestedPrice == 45.0)
        #expect(item.priceSource == "mock_fixture")
        #expect(item.brand == "Acme")
        #expect(item.imageUrls.count == 1)
        #expect(item.provider == "mock")
    }

    @Test("Unpriced item decodes nulls, never zero")
    func itemUnpriced() throws {
        let item = try decode(Item.self, Fixtures.itemUnpriced)
        #expect(item.suggestedPrice == nil)
        #expect(item.suggestedPrice != 0.0)
        #expect(item.brand == nil)
        #expect(item.priceSource == "none")
        #expect(item.createdAt == nil)
    }

    @Test("ItemPatch omits unset fields")
    func itemPatchEncoding() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(ItemPatch(title: "Sealed box (lot)", needsReview: false))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"title\""))
        #expect(json.contains("\"needs_review\""))
        #expect(!json.contains("suggested_price"))
        #expect(!json.contains("description"))
    }

    @Test("ItemPatch price clear encodes explicit null")
    func itemPatchClearPrice() throws {
        let data = try JSONEncoder().encode(ItemPatch.clearingPrice)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"suggested_price\":null"))
    }

    @Test("JobCreated decodes")
    func jobCreated() throws {
        let created = try decode(JobCreated.self, Fixtures.jobCreated)
        #expect(created.id == Fixtures.jobId)
        #expect(created.status == .queued)
        #expect(!created.status.isTerminal)
    }

    @Test("PalletCreate encodes snake_case")
    func palletCreateEncoding() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(PalletCreate(
            name: "Bin 12", purchaseCost: 20.0, additionalCosts: 5.0, jobId: Fixtures.jobId))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"purchase_cost\":20"))
        #expect(json.contains("\"additional_costs\":5"))
        #expect(json.contains("\"job_id\":\"\(Fixtures.jobId)\""))
        #expect(!json.contains("purchaseCost"))
    }

    @Test("UploadVideo rejects unsupported extensions")
    func uploadVideoValidation() {
        #expect(throws: APIError.self) {
            try UploadVideo(data: Data([0x00]), fileExtension: "txt")
        }
        let video = try? UploadVideo(data: Data([0x00]), fileExtension: "MOV")
        #expect(video?.filename == "video.mov")
        #expect(video?.mimeType == "video/quicktime")
    }
}
