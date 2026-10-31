import Foundation
@testable import PalletPilot

/// Backend-shaped fixtures. Shapes mirror `backend/tests/test_phase2.py` and
/// docs/ios/API_CONTRACTS.md — never invented fields.
enum Fixtures {
    static let jobId = "abc123def4567890abc123def4567890"
    static let palletId = "9f3c1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

    static let jobCreated = """
    {"id": "\(jobId)", "status": "queued"}
    """

    static let jobQueued = """
    {
      "id": "\(jobId)",
      "status": "queued",
      "created_at": "2026-10-28T12:00:00.123456+00:00",
      "updated_at": "2026-10-28T12:00:00.123456+00:00",
      "video_filename": "video.mp4",
      "frame_count": 0,
      "listings": [],
      "error": null
    }
    """

    static let jobFailed = """
    {
      "id": "\(jobId)",
      "status": "failed",
      "created_at": "2026-10-28T12:00:00.123456+00:00",
      "updated_at": "2026-10-28T12:00:05.123456+00:00",
      "video_filename": "video.mp4",
      "frame_count": 0,
      "listings": [],
      "error": "Could not open video: video.mp4"
    }
    """

    static let health = #"{"status": "ok"}"#

    static let jobCompleted = """
    {
      "id": "\(jobId)",
      "status": "completed",
      "created_at": "2026-10-28T12:00:00.123456+00:00",
      "updated_at": "2026-10-28T12:00:05.123456+00:00",
      "video_filename": "video.mp4",
      "frame_count": 6,
      "listings": [
        {
          "item_id": "\(jobId):item_0",
          "title": "Acme Cordless Drill",
          "description": "Acme Cordless Drill (Power Tools). Demo draft: verify before posting.",
          "category": "Power Tools",
          "brand": "Acme",
          "condition": "good",
          "price": {"amount": 45.0, "currency": "USD"},
          "image_urls": ["/jobs/\(jobId)/files/photos/item_0_0.jpg"],
          "confidence": 0.85,
          "needs_review": true,
          "review_reasons": ["mock identification: not verified against imagery"]
        }
      ],
      "error": null
    }
    """

    static let pallet = """
    {
      "id": "\(palletId)",
      "name": "Bin 12",
      "purchase_cost": 20.0,
      "additional_costs": 5.0,
      "job_id": null,
      "status": "empty",
      "item_count": 0,
      "priced_item_count": 0,
      "created_at": "2026-10-28T12:00:00.123456+00:00",
      "updated_at": "2026-10-28T12:00:00.123456+00:00"
    }
    """

    static let palletSummary = """
    {
      "pallet": \(palletReady),
      "estimated_revenue": 77.5,
      "estimated_fees": 10.07,
      "projected_profit": 42.43,
      "fee_rate": 0.13,
      "unpriced_item_count": 1,
      "estimates": true
    }
    """

    static let palletReady = """
    {
      "id": "\(palletId)",
      "name": "Demo pallet",
      "purchase_cost": 20.0,
      "additional_costs": 5.0,
      "job_id": "\(jobId)",
      "status": "ready",
      "item_count": 3,
      "priced_item_count": 2,
      "created_at": "2026-10-28T12:00:00.123456+00:00",
      "updated_at": "2026-10-28T12:00:05.123456+00:00"
    }
    """

    static let itemPriced = """
    {
      "id": "\(jobId):item_0",
      "pallet_id": "\(palletId)",
      "job_id": "\(jobId)",
      "track_id": "track_00003",
      "title": "Acme Cordless Drill",
      "description": "Acme Cordless Drill (Power Tools).",
      "category": "Power Tools",
      "brand": "Acme",
      "condition": "good",
      "suggested_price": 45.0,
      "currency": "USD",
      "price_source": "mock_fixture",
      "price_confidence": 0.4,
      "price_type": "asking",
      "original_image_url": "/jobs/\(jobId)/files/frames/frame_00003.jpg",
      "image_urls": ["/jobs/\(jobId)/files/photos/item_0_0.jpg"],
      "confidence": 0.85,
      "needs_review": true,
      "review_reasons": ["mock identification: not verified against imagery"],
      "provider": "mock",
      "created_at": "2026-10-28T12:00:05.123456+00:00",
      "updated_at": "2026-10-28T12:00:05.123456+00:00"
    }
    """

    static let itemUnpriced = """
    {
      "id": "\(jobId):item_2",
      "pallet_id": "\(palletId)",
      "job_id": "\(jobId)",
      "track_id": "track_00010",
      "title": "Unidentified sealed box",
      "description": "",
      "category": "Uncategorized",
      "brand": null,
      "condition": "unknown",
      "suggested_price": null,
      "currency": "USD",
      "price_source": "none",
      "price_confidence": null,
      "price_type": "unknown",
      "original_image_url": null,
      "image_urls": [],
      "confidence": 0.1,
      "needs_review": true,
      "review_reasons": ["mock identification: not verified against imagery"],
      "provider": "mock",
      "created_at": null,
      "updated_at": null
    }
    """
}

/// URLProtocol stub for `APIClient` tests. Queue one response per request:
/// `MockURLProtocol.queued = [(data, statusCode)]` or `.queuedError`.
final class MockURLProtocol: URLProtocol {
    struct StubbedResponse {
        var data: Data
        var statusCode: Int
    }

    static var queued: [StubbedResponse] = []
    static var queuedError: Error?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.queuedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let stub = Self.queued.isEmpty
            ? StubbedResponse(data: Data(), statusCode: 200)
            : Self.queued.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        queued = []
        queuedError = nil
        lastRequest = nil
    }

    /// Session routing every request through the stub queue.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Reads a recorded request body whether URLSession kept it in `httpBody`
/// or moved it to `httpBodyStream`.
enum RecordedBody {
    static func string(_ request: URLRequest) -> String? {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Fake health service for ViewModel tests.
struct FakeHealthService: HealthServiceProtocol {
    var result: Result<HealthResponse, Error>

    func checkHealth() async throws -> HealthResponse {
        try result.get()
    }
}

/// Fake pallet service returning a canned pallet.
final class FakePalletService: PalletServiceProtocol {
    var result: Result<Pallet, Error>
    private(set) var created: [PalletCreate] = []

    init(result: Result<Pallet, Error>) {
        self.result = result
    }

    func createPallet(_ create: PalletCreate) async throws -> Pallet {
        created.append(create)
        return try result.get()
    }
}

/// Fake job service with a scripted status sequence for polling tests.
final class FakeJobService: JobServiceProtocol {
    var uploadResult: Result<JobCreated, Error> = .failure(APIError.invalidRequest("unset"))
    var statuses: [Job]
    private(set) var calls = 0
    private(set) var uploadedPalletId: String?

    init(statuses: [Job] = []) {
        self.statuses = statuses
    }

    func uploadVideo(_ video: UploadVideo, palletId: String?) async throws -> JobCreated {
        uploadedPalletId = palletId
        return try uploadResult.get()
    }

    func getJob(id: String) async throws -> Job {
        calls += 1
        return statuses[min(calls - 1, statuses.count - 1)]
    }

    func listJobs() async throws -> [Job] {
        statuses
    }
}
