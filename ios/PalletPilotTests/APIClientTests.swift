import Foundation
import XCTest
@testable import PalletPilot

/// Networking behavior tests (XCTest): URL construction, status handling, and
/// ViewModel wiring with injected fakes. No live backend required.
final class APIClientTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        client = APIClient(
            configuration: .init(baseURL: URL(string: "http://127.0.0.1:8000")!),
            session: MockURLProtocol.session()
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testHealthSuccessDecodes() async throws {
        MockURLProtocol.queued = [.init(data: Data(Fixtures.health.utf8), statusCode: 200)]
        let health: HealthResponse = try await client.get("/health", as: HealthResponse.self)
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "http://127.0.0.1:8000/health")
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "GET")
    }

    func testExactPathHasNoTrailingSlash() async throws {
        MockURLProtocol.queued = [.init(data: Data(Fixtures.health.utf8), statusCode: 200)]
        _ = try await client.get("/health", as: HealthResponse.self)
        XCTAssertFalse(MockURLProtocol.lastRequest?.url?.absoluteString.hasSuffix("/") ?? true)
    }

    func test404MapsToNotFoundWithDetail() async {
        MockURLProtocol.queued = [.init(
            data: Data(#"{"detail": "Job not found"}"#.utf8), statusCode: 404)]
        do {
            _ = try await client.get("/jobs/nope", as: Job.self)
            XCTFail("Expected 404")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(statusCode: 404, detail: "Job not found"))
            XCTAssertEqual(error.errorDescription, "Job not found")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test409MapsToConflict() async {
        MockURLProtocol.queued = [.init(
            data: Data(#"{"detail": "Job is already linked to a pallet"}"#.utf8), statusCode: 409)]
        do {
            _ = try await client.get("/pallets", as: Job.self)
            XCTFail("Expected 409")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(statusCode: 409, detail: "Job is already linked to a pallet"))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test422WithoutDetailEnvelopeFallsBackToGenericMessage() async {
        // 422 bodies are FastAPI validation envelopes, not {"detail": string}.
        MockURLProtocol.queued = [.init(
            data: Data(#"{"detail": [{"loc": ["body"], "msg": "err"}]}"#.utf8), statusCode: 422)]
        do {
            _ = try await client.get("/items/x", as: Item.self)
            XCTFail("Expected 422")
        } catch let error as APIError {
            if case .http(let code, _) = error {
                XCTAssertEqual(code, 422)
            } else {
                XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(error.errorDescription, "The server rejected this request (422).")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMalformedBodyMapsToDecoding() async {
        MockURLProtocol.queued = [.init(data: Data("not json".utf8), statusCode: 200)]
        do {
            _ = try await client.get("/health", as: HealthResponse.self)
            XCTFail("Expected decoding failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .decoding(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testTransportFailureMapsToNetwork() async {
        MockURLProtocol.queuedError = URLError(.notConnectedToInternet)
        do {
            _ = try await client.get("/health", as: HealthResponse.self)
            XCTFail("Expected network failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .network(URLError(.notConnectedToInternet)))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testHomeViewModelConnectsOnHealthyResponse() async {
        let viewModel = await MainActor.run {
            HomeViewModel(
                healthService: FakeHealthService(result: .success(HealthResponse(status: "ok"))),
                baseURLDescription: "http://127.0.0.1:8000"
            )
        }
        await viewModel.checkConnection()
        let state = await viewModel.connection
        XCTAssertEqual(state, .connected(serverStatus: "ok"))
    }

    func testHomeViewModelSurfacesFailureMessage() async {
        let viewModel = await MainActor.run {
            HomeViewModel(
                healthService: FakeHealthService(
                    result: .failure(APIError.http(statusCode: 500, detail: nil))),
                baseURLDescription: "http://127.0.0.1:8000"
            )
        }
        await viewModel.checkConnection()
        let state = await viewModel.connection
        XCTAssertEqual(state, .failed(message: "Server error (500)."))
    }

    // MARK: - Upload + processing

    private func testDecoder() -> JSONDecoder {
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
                in: container, debugDescription: "bad date")
        }
        return decoder
    }

    func testCreatePalletPostsSnakeCaseJSON() async throws {
        MockURLProtocol.queued = [.init(data: Data(Fixtures.pallet.utf8), statusCode: 201)]
        let pallet: Pallet = try await client.post(
            "/pallets",
            body: PalletCreate(name: "Bin 12", purchaseCost: 20.0, additionalCosts: 5.0),
            as: Pallet.self)
        XCTAssertEqual(pallet.name, "Bin 12")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(RecordedBody.string(request))
        XCTAssertTrue(body.contains("\"purchase_cost\":20"))
        XCTAssertTrue(body.contains("\"additional_costs\":5"))
        XCTAssertFalse(body.contains("purchaseCost"))
    }

    func testUploadVideoSendsMultipartWithPalletId() async throws {
        MockURLProtocol.queued = [.init(data: Data(Fixtures.jobCreated.utf8), statusCode: 202)]
        let video = try UploadVideo(data: Data([0x00, 0x01]), fileExtension: "mp4")
        let created: JobCreated = try await client.upload(
            "/jobs", fileData: video.data, filename: video.filename,
            mimeType: video.mimeType, fields: ["pallet_id": Fixtures.palletId],
            as: JobCreated.self)
        XCTAssertEqual(created.id, Fixtures.jobId)
        XCTAssertEqual(created.status, .queued)
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(RecordedBody.string(request))
        XCTAssertTrue(body.contains("name=\"pallet_id\""))
        XCTAssertTrue(body.contains(Fixtures.palletId))
        XCTAssertTrue(body.contains("name=\"video\"; filename=\"video.mp4\""))
        XCTAssertTrue(body.contains("Content-Type: video/mp4"))
    }

    func testUploadConflictSurfacesDetail() async {
        MockURLProtocol.queued = [.init(
            data: Data(#"{"detail": "Pallet already has a job"}"#.utf8), statusCode: 409)]
        let video = try? UploadVideo(data: Data([0x00]), fileExtension: "mp4")
        do {
            _ = try await client.upload(
                "/jobs", fileData: video!.data, filename: video!.filename,
                mimeType: video!.mimeType, fields: ["pallet_id": "x"],
                as: JobCreated.self)
            XCTFail("Expected 409")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(statusCode: 409, detail: "Pallet already has a job"))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testUploadViewModelCreatesPalletThenUploads() async throws {
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        let jobService = FakeJobService()
        jobService.uploadResult = .success(JobCreated(id: Fixtures.jobId, status: .queued))
        let viewModel = await MainActor.run {
            UploadViewModel(palletService: palletService, jobService: jobService)
        }
        await MainActor.run {
            viewModel.palletName = "Bin 12"
            viewModel.setVideo(data: Data([0x00]), fileExtension: "mp4")
        }
        await viewModel.startUpload()
        let state = await viewModel.state
        XCTAssertEqual(state, .uploaded(jobId: Fixtures.jobId, palletId: Fixtures.palletId))
        XCTAssertEqual(palletService.created.count, 1)
        XCTAssertEqual(palletService.created.first?.name, "Bin 12")
        XCTAssertEqual(jobService.uploadedPalletId, Fixtures.palletId)
    }

    func testUploadViewModelRetryReusesPallet() async throws {
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        let jobService = FakeJobService()
        jobService.uploadResult = .failure(APIError.http(statusCode: 413, detail: "Video too large"))
        let viewModel = await MainActor.run {
            UploadViewModel(palletService: palletService, jobService: jobService)
        }
        await MainActor.run { viewModel.setVideo(data: Data([0x00]), fileExtension: "mp4") }
        await viewModel.startUpload()
        let first = await viewModel.state
        XCTAssertEqual(first, .failed(message: "Video too large"))
        jobService.uploadResult = .success(JobCreated(id: Fixtures.jobId, status: .queued))
        await viewModel.startUpload()
        let second = await viewModel.state
        XCTAssertEqual(second, .uploaded(jobId: Fixtures.jobId, palletId: Fixtures.palletId))
        XCTAssertEqual(palletService.created.count, 1, "retry must not create a second pallet")
    }

    func testProcessingViewModelPollsToCompletion() async throws {
        let decoder = testDecoder()
        let queued = try decoder.decode(Job.self, from: Data(Fixtures.jobQueued.utf8))
        let done = try decoder.decode(Job.self, from: Data(Fixtures.jobCompleted.utf8))
        let jobService = FakeJobService(statuses: [queued, queued, done])
        let viewModel = await MainActor.run {
            ProcessingViewModel(jobService: jobService, jobId: Fixtures.jobId,
                                pollInterval: 0.01, timeout: 5)
        }
        await viewModel.start()
        // Wait for the terminal state without sleeping the full timeout.
        for _ in 0..<200 {
            let state = await viewModel.state
            if case .completed = state { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await viewModel.stop()
        let state = await viewModel.state
        XCTAssertEqual(state, .completed(job: done))
        XCTAssertGreaterThanOrEqual(jobService.calls, 2)
    }

    func testProcessingViewModelSurfacesJobError() async throws {
        let failed = try testDecoder().decode(Job.self, from: Data(Fixtures.jobFailed.utf8))
        let jobService = FakeJobService(statuses: [failed])
        let viewModel = await MainActor.run {
            ProcessingViewModel(jobService: jobService, jobId: Fixtures.jobId,
                                pollInterval: 0.01, timeout: 5)
        }
        await viewModel.start()
        for _ in 0..<200 {
            let state = await viewModel.state
            if case .failed = state { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await viewModel.stop()
        let state = await viewModel.state
        XCTAssertEqual(state, .failed(message: "Could not open video: video.mp4"))
    }

    func testProcessingViewModelTimesOut() async throws {
        let queued = try testDecoder().decode(Job.self, from: Data(Fixtures.jobQueued.utf8))
        let jobService = FakeJobService(statuses: [queued])
        let viewModel = await MainActor.run {
            ProcessingViewModel(jobService: jobService, jobId: Fixtures.jobId,
                                pollInterval: 0.05, timeout: 0.12)
        }
        await viewModel.start()
        for _ in 0..<200 {
            let state = await viewModel.state
            if case .timedOut = state { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await viewModel.stop()
        let state = await viewModel.state
        XCTAssertEqual(state, .timedOut)
    }
}
