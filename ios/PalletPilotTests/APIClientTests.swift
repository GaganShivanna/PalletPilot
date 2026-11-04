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
        let suite = UserDefaults(suiteName: "PalletPilotUploadTests")!
        suite.removePersistentDomain(forName: "PalletPilotUploadTests")
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        let jobService = FakeJobService()
        jobService.uploadResult = .success(JobCreated(id: Fixtures.jobId, status: .queued))
        let viewModel = await MainActor.run {
            UploadViewModel(
                palletService: palletService, jobService: jobService,
                historyStore: PalletHistoryStore(defaults: suite))
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
        suite.removePersistentDomain(forName: "PalletPilotUploadTests")
    }

    func testUploadViewModelRetryReusesPallet() async throws {
        let suite = UserDefaults(suiteName: "PalletPilotUploadRetryTests")!
        suite.removePersistentDomain(forName: "PalletPilotUploadRetryTests")
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        let jobService = FakeJobService()
        jobService.uploadResult = .failure(APIError.http(statusCode: 413, detail: "Video too large"))
        let viewModel = await MainActor.run {
            UploadViewModel(
                palletService: palletService, jobService: jobService,
                historyStore: PalletHistoryStore(defaults: suite))
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
        suite.removePersistentDomain(forName: "PalletPilotUploadRetryTests")
    }

    private func liveViewModel(
        statuses: [Job], frames: [ServerSentEvent] = [], streamError: Error? = nil
    ) async -> (ProcessingViewModel, FakeJobService, FakeSSEClient) {
        let jobService = FakeJobService(statuses: statuses)
        let sse = FakeSSEClient()
        sse.frames = frames
        sse.error = streamError
        let viewModel = await MainActor.run {
            ProcessingViewModel(
                jobService: jobService, jobId: Fixtures.jobId,
                pollInterval: 0.01, timeout: 5,
                sseClient: sse,
                baseURL: URL(string: "http://127.0.0.1:8000")!)
        }
        return (viewModel, jobService, sse)
    }

    private func eventData(id: Int, type: String, itemId: String? = nil) -> String {
        let item = itemId.map { "\"\($0)\"" } ?? "null"
        return """
            {"id": \(id), "job_id": "\(Fixtures.jobId)", "event_type": "\(type)", \
            "item_id": \(item), "created_at": "2026-10-28T12:00:05.123456+00:00", \
            "payload": {}}
            """
    }

    private func waitForTerminal(_ viewModel: ProcessingViewModel) async -> ProcessingState {
        for _ in 0..<200 {
            let state = await viewModel.state
            if case .completed = state { return state }
            if case .failed = state { return state }
            if case .timedOut = state { return state }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await viewModel.state
    }

    func testJobEventDecodesEnvelopeIgnoringPayload() throws {
        let event = try testDecoder().decode(
            JobEvent.self,
            from: Data(eventData(
                id: 7, type: "listing.ready",
                itemId: "\(Fixtures.jobId):item_0").utf8))
        XCTAssertEqual(event.id, 7)
        XCTAssertEqual(event.jobId, Fixtures.jobId)
        XCTAssertEqual(event.eventType, "listing.ready")
        XCTAssertEqual(event.itemId, "\(Fixtures.jobId):item_0")
        XCTAssertFalse(event.isTerminal)
        let done = try testDecoder().decode(
            JobEvent.self, from: Data(eventData(id: 8, type: "job.completed").utf8))
        XCTAssertTrue(done.isTerminal)
        XCTAssertTrue(done.didComplete)
    }

    func testProcessingStartLiveCompletesOnTerminalEvent() async throws {
        let decoder = testDecoder()
        let done = try decoder.decode(Job.self, from: Data(Fixtures.jobCompleted.utf8))
        let frame = ServerSentEvent(
            id: 3, eventType: "job.completed", data: eventData(id: 3, type: "job.completed"))
        let (viewModel, _, sse) = await liveViewModel(statuses: [done], frames: [frame])
        await viewModel.startLive()
        let state = await waitForTerminal(viewModel)
        await viewModel.stop()
        if case .completed(let job) = state {
            XCTAssertEqual(job.id, Fixtures.jobId)
        } else {
            XCTFail("Expected completed, got \(state)")
        }
        XCTAssertEqual(sse.urls.count, 1)
        XCTAssertEqual(
            sse.urls.first?.absoluteString,
            "http://127.0.0.1:8000/jobs/\(Fixtures.jobId)/events")
    }

    func testProcessingStartLiveDedupesRepeatedEvents() async throws {
        let decoder = testDecoder()
        let queued = try decoder.decode(Job.self, from: Data(Fixtures.jobQueued.utf8))
        let done = try decoder.decode(Job.self, from: Data(Fixtures.jobCompleted.utf8))
        let ready = eventData(id: 1, type: "listing.ready", itemId: "\(Fixtures.jobId):item_0")
        let frames = [
            ServerSentEvent(id: 1, eventType: "listing.ready", data: ready),
            ServerSentEvent(id: 1, eventType: "listing.ready", data: ready),
            ServerSentEvent(
                id: 2, eventType: "job.completed",
                data: eventData(id: 2, type: "job.completed")),
        ]
        let (viewModel, jobService, _) = await liveViewModel(
            statuses: [queued, done], frames: frames)
        await viewModel.startLive()
        let state = await waitForTerminal(viewModel)
        await viewModel.stop()
        // One refresh for the first listing.ready, none for the duplicate,
        // one final fetch for the terminal event.
        XCTAssertEqual(jobService.calls, 2)
        if case .completed = state {} else {
            XCTFail("Expected completed, got \(state)")
        }
    }

    func testProcessingStartLiveFallsBackToPollOnStreamError() async throws {
        let decoder = testDecoder()
        let queued = try decoder.decode(Job.self, from: Data(Fixtures.jobQueued.utf8))
        let done = try decoder.decode(Job.self, from: Data(Fixtures.jobCompleted.utf8))
        let (viewModel, _, sse) = await liveViewModel(
            statuses: [queued, done], streamError: URLError(.timedOut))
        await viewModel.startLive()
        let state = await waitForTerminal(viewModel)
        await viewModel.stop()
        if case .completed = state {} else {
            XCTFail("Expected poll fallback to complete, got \(state)")
        }
        XCTAssertEqual(sse.lastEventIDs.count, 1)
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

    // MARK: - Design screens (inventory / detail / summary / export)

    private func testItems() throws -> [Item] {
        let decoder = testDecoder()
        return try [
            decoder.decode(Item.self, from: Data(Fixtures.itemPriced.utf8)),
            decoder.decode(Item.self, from: Data(Fixtures.itemUnpriced.utf8)),
        ]
    }

    private func testSummary() throws -> PalletSummary {
        try testDecoder().decode(PalletSummary.self, from: Data(Fixtures.palletSummary.utf8))
    }

    func testPatchSendsPatchMethodWithSnakeCaseKeys() async throws {
        MockURLProtocol.queued = [.init(data: Data(Fixtures.itemPriced.utf8), statusCode: 200)]
        var patch = ItemPatch()
        patch.title = "Retitled"
        patch.needsReview = false
        let item: Item = try await client.patch(
            "/items/\(Fixtures.jobId):item_0", body: patch, as: Item.self)
        XCTAssertEqual(item.id, "\(Fixtures.jobId):item_0")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertFalse(request.url?.absoluteString.hasSuffix("/") ?? true)
        let body = try XCTUnwrap(RecordedBody.string(request))
        XCTAssertTrue(body.contains("\"title\":\"Retitled\""))
        XCTAssertTrue(body.contains("\"needs_review\":false"))
        XCTAssertFalse(body.contains("suggested_price"))
    }

    func testInventoryViewModelLoadsAndFilters() async throws {
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let service = FakePalletService(result: .success(pallet))
        service.itemsResult = .success(try testItems())
        service.summaryResult = .success(try testSummary())
        let viewModel = await MainActor.run {
            InventoryViewModel(palletId: Fixtures.palletId, palletService: service)
        }
        await viewModel.load()
        let state = await viewModel.state
        XCTAssertEqual(state, .loaded)
        let needsReviewCount = await viewModel.needsReviewCount
        XCTAssertEqual(needsReviewCount, 2)
        let noPriceCount = await viewModel.noPriceCount
        XCTAssertEqual(noPriceCount, 1)
        let allTitle = await viewModel.filterTitle(.all)
        XCTAssertEqual(allTitle, "All 2")
        await MainActor.run { viewModel.filter = .noPrice }
        let noPriceItems = await viewModel.filteredItems
        XCTAssertEqual(noPriceItems.count, 1)
        await MainActor.run { viewModel.filter = .needsReview }
        let reviewItems = await viewModel.filteredItems
        XCTAssertEqual(reviewItems.count, 2)
    }

    func testItemDetailViewModelSaveSendsChangedKeys() async throws {
        let service = FakeItemService(item: try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8)))
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
        }
        await viewModel.load()
        let loadedState = await viewModel.state
        XCTAssertEqual(loadedState, .loaded)
        await MainActor.run {
            viewModel.title = "Retitled drill"
            viewModel.markReviewed = true
        }
        await viewModel.save()
        let savedState = await viewModel.state
        XCTAssertEqual(savedState, .loaded)
        XCTAssertEqual(service.patched.count, 1)
        XCTAssertEqual(service.patched.first?.patch.title, "Retitled drill")
        XCTAssertEqual(service.patched.first?.patch.needsReview, false)
        XCTAssertNil(service.patched.first?.patch.suggestedPrice)
    }

    func testSummaryViewModelRanksTopItemsByPrice() async throws {
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let service = FakePalletService(result: .success(pallet))
        service.summaryResult = .success(try testSummary())
        service.itemsResult = .success(try testItems())
        let viewModel = await MainActor.run {
            SummaryViewModel(palletId: Fixtures.palletId, palletService: service)
        }
        await viewModel.load()
        let summaryState = await viewModel.state
        XCTAssertEqual(summaryState, .loaded)
        let top = await viewModel.topItems
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.suggestedPrice, 45.0)
        let feePercent = await viewModel.feeRatePercent
        XCTAssertEqual(feePercent, 13)
    }

    func testExportViewModelCounts() async throws {
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let service = FakePalletService(result: .success(pallet))
        service.itemsResult = .success(try testItems())
        let viewModel = await MainActor.run {
            ExportViewModel(palletId: Fixtures.palletId, palletService: service)
        }
        await viewModel.load()
        let exportState = await viewModel.state
        XCTAssertEqual(exportState, .loaded)
        let reviewed = await viewModel.reviewedCount
        XCTAssertEqual(reviewed, 0)
        let unreviewed = await viewModel.unreviewedCount
        XCTAssertEqual(unreviewed, 2)
        let donate = await viewModel.donateCount
        XCTAssertEqual(donate, 1)
    }

    func testExportFilteredCSVDropsUnreviewedRows() {
        let csv = """
            item_id,title,description,category,brand,condition,suggested_price,currency,image_url,review_status
            a1,Drill,,Power Tools,Acme,good,45.0,USD,/f/1.jpg,approved
            a2,"Box, sealed",,Uncategorized,,unknown,,USD,,needs_review
            """
        let filtered = ExportViewModel.filteredCSV(Data((csv + "\n").utf8), includeUnreviewed: false)
        let text = String(data: filtered ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("a1,Drill"))
        XCTAssertFalse(text.contains("a2"))
        XCTAssertTrue(text.hasPrefix("item_id,"))
        let kept = ExportViewModel.filteredCSV(Data((csv + "\n").utf8), includeUnreviewed: true)
        XCTAssertEqual(kept, Data((csv + "\n").utf8))
    }

    func testExportFetchCSVAppliesToggle() async throws {
        let csv = """
            item_id,title,description,category,brand,condition,suggested_price,currency,image_url,review_status
            a1,Drill,,Power Tools,Acme,good,45.0,USD,/f/1.jpg,approved
            a2,Box,,Uncategorized,,unknown,,USD,,needs_review
            """ + "\n"
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let service = FakePalletService(result: .success(pallet))
        service.itemsResult = .success(try testItems())
        service.exportResult = .success(Data(csv.utf8))
        let viewModel = await MainActor.run {
            ExportViewModel(palletId: Fixtures.palletId, palletService: service)
        }
        await viewModel.load()
        await viewModel.fetchCSV()
        let offData = await viewModel.csvData
        let off = String(data: try XCTUnwrap(offData), encoding: .utf8) ?? ""
        XCTAssertTrue(off.contains("a1,Drill"))
        XCTAssertFalse(off.contains("a2"))
        await MainActor.run { viewModel.includeUnreviewed = true }
        await viewModel.fetchCSV()
        let onData = await viewModel.csvData
        let on = String(data: try XCTUnwrap(onData), encoding: .utf8) ?? ""
        XCTAssertTrue(on.contains("a2"))
        let count = await viewModel.exportedCount
        XCTAssertEqual(count, 2)
    }

    func testItemDetailSaveRejectsInvalidPrice() async throws {
        let service = FakeItemService(item: try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8)))
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
        }
        await viewModel.load()
        await MainActor.run { viewModel.priceText = "abc" }
        await viewModel.save()
        let abcError = await viewModel.priceError
        XCTAssertNotNil(abcError)
        XCTAssertTrue(service.patched.isEmpty)
    }

    func testItemDetailSaveShowsConfirmation() async throws {
        let service = FakeItemService(item: try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8)))
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
        }
        await viewModel.load()
        await MainActor.run {
            viewModel.title = "Retitled drill"
        }
        await viewModel.save()
        let message = await viewModel.saveMessage
        let savedState = await viewModel.state
        XCTAssertEqual(message, "Saved.")
        XCTAssertEqual(savedState, .loaded)
    }

    func testHomeViewModelLoadsRecentStatuses() async throws {
        let suite = UserDefaults(suiteName: "PalletPilotHomeStatusTests")!
        suite.removePersistentDomain(forName: "PalletPilotHomeStatusTests")
        let store = PalletHistoryStore(defaults: suite)
        store.save(palletId: Fixtures.palletId, jobId: Fixtures.jobId, name: "Bin 12")
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        palletService.summaryResult = .success(try testSummary())
        let viewModel = await MainActor.run {
            HomeViewModel(
                healthService: FakeHealthService(result: .success(HealthResponse(status: "ok"))),
                baseURLDescription: "http://127.0.0.1:8000",
                historyStore: store,
                palletService: palletService)
        }
        await MainActor.run { viewModel.refreshRecents() }
        for _ in 0..<100 {
            let statuses = await viewModel.recentStatuses
            if statuses[Fixtures.palletId] != nil { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let statuses = await viewModel.recentStatuses
        XCTAssertEqual(statuses[Fixtures.palletId], "ready")
        suite.removePersistentDomain(forName: "PalletPilotHomeStatusTests")
    }

    func testItemDetailSaveRejectsNegativePrice() async throws {
        let service = FakeItemService(item: try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8)))
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
        }
        await viewModel.load()
        await MainActor.run { viewModel.priceText = "-5" }
        await viewModel.save()
        let negativeError = await viewModel.priceError
        XCTAssertNotNil(negativeError)
        XCTAssertTrue(service.patched.isEmpty)
    }

    func testItemDetailPhotoTabsNeedRealURLs() async throws {
        let priced = try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8))
        let pricedService = FakeItemService(item: priced)
        let pricedViewModel = await MainActor.run {
            ItemDetailViewModel(itemId: priced.id, itemService: pricedService)
        }
        await pricedViewModel.load()
        let pricedTabs = await pricedViewModel.availablePhotoTabs
        let pricedCaption = await pricedViewModel.cleanPhotoCaption
        XCTAssertEqual(pricedTabs, [.clean, .original])
        XCTAssertEqual(pricedCaption, "AI photo")

        let unpriced = try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemUnpriced.utf8))
        let unpricedService = FakeItemService(item: unpriced)
        let unpricedViewModel = await MainActor.run {
            ItemDetailViewModel(itemId: unpriced.id, itemService: unpricedService)
        }
        await unpricedViewModel.load()
        let unpricedTabs = await unpricedViewModel.availablePhotoTabs
        let unpricedCaption = await unpricedViewModel.cleanPhotoCaption
        XCTAssertEqual(unpricedTabs, [.original])
        XCTAssertEqual(unpricedCaption, "No photo yet")
    }

    func testItemDetailPhotoFallbackCaptionIsHonest() async throws {
        let fallbackJSON = Fixtures.itemPriced.replacingOccurrences(
            of: "/files/photos/item_0_0.jpg", with: "/files/frames/frame_00003.jpg")
        let item = try testDecoder().decode(Item.self, from: Data(fallbackJSON.utf8))
        let service = FakeItemService(item: item)
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: item.id, itemService: service)
        }
        await viewModel.load()
        let fallbackCaption = await viewModel.cleanPhotoCaption
        XCTAssertEqual(fallbackCaption, "Original crop (no AI cleanup available)")
    }

    func testCaptureAttachSetsServerData() async throws {
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        palletService.itemsResult = .success(try testItems())
        palletService.summaryResult = .success(try testSummary())
        let viewModel = await MainActor.run {
            CaptureViewModel(
                jobService: FakeJobService(),
                palletService: palletService)
        }
        let initial = await viewModel.hasServerData
        XCTAssertFalse(initial)
        await viewModel.attach(palletId: Fixtures.palletId, jobId: Fixtures.jobId)
        let attached = await viewModel.hasServerData
        let found = await viewModel.itemsFound
        XCTAssertTrue(attached)
        XCTAssertEqual(found, 2)
    }

    func testPalletHistoryStoreRoundTrip() {
        let suite = UserDefaults(suiteName: "PalletPilotHistoryTests")!
        suite.removePersistentDomain(forName: "PalletPilotHistoryTests")
        let store = PalletHistoryStore(defaults: suite)
        XCTAssertTrue(store.recents().isEmpty)
        store.save(palletId: "p1", jobId: nil, name: "Bin 12")
        store.save(palletId: "p2", jobId: "j2", name: "Bin 13")
        let recents = store.recents()
        XCTAssertEqual(recents.map(\.palletId), ["p2", "p1"])
        XCTAssertEqual(store.palletId(forJobId: "j2"), "p2")
        XCTAssertNil(store.palletId(forJobId: "unknown"))
        store.save(palletId: "p1", jobId: "j1", name: "Bin 12 renamed")
        XCTAssertEqual(store.recents().map(\.palletId), ["p1", "p2"])
        XCTAssertEqual(store.palletId(forJobId: "j1"), "p1")
        store.remove(palletId: "p2")
        XCTAssertEqual(store.recents().map(\.palletId), ["p1"])
        suite.removePersistentDomain(forName: "PalletPilotHistoryTests")
    }

    func testHistoryViewModelLoadsJobs() async throws {
        let decoder = testDecoder()
        let queued = try decoder.decode(Job.self, from: Data(Fixtures.jobQueued.utf8))
        let done = try decoder.decode(Job.self, from: Data(Fixtures.jobCompleted.utf8))
        let viewModel = await MainActor.run {
            HistoryViewModel(jobService: FakeJobService(statuses: [queued, done]))
        }
        await viewModel.load()
        let state = await viewModel.state
        XCTAssertEqual(state, .loaded)
        let jobs = await viewModel.jobs
        XCTAssertEqual(jobs.count, 2)
        let linked = await viewModel.palletId(for: Fixtures.jobId)
        XCTAssertNil(linked)
    }

    func testHistoryViewModelSurfacesFailure() async throws {
        let jobService = FakeJobService()
        jobService.listError = APIError.http(statusCode: 500, detail: nil)
        let viewModel = await MainActor.run {
            HistoryViewModel(jobService: jobService)
        }
        await viewModel.load()
        let state = await viewModel.state
        XCTAssertEqual(state, .failed(message: "Server error (500)."))
    }

    func testUploadViewModelAdoptsPendingPallet() async throws {
        let suite = UserDefaults(suiteName: "PalletPilotPendingAdoptTests")!
        suite.removePersistentDomain(forName: "PalletPilotPendingAdoptTests")
        let store = PalletHistoryStore(defaults: suite)
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let firstPalletService = FakePalletService(result: .success(pallet))
        let failingJobs = FakeJobService()
        failingJobs.uploadResult = .failure(APIError.http(statusCode: 500, detail: nil))
        let first = await MainActor.run {
            UploadViewModel(
                palletService: firstPalletService, jobService: failingJobs,
                historyStore: store)
        }
        await MainActor.run {
            first.palletName = "Bin 12"
            first.setVideo(data: Data([0x00]), fileExtension: "mp4")
        }
        await first.startUpload()
        XCTAssertEqual(firstPalletService.created.count, 1)

        // Fresh ViewModel, same draft: must adopt, not create a second pallet.
        let secondPalletService = FakePalletService(result: .success(pallet))
        let succeedingJobs = FakeJobService()
        succeedingJobs.uploadResult = .success(JobCreated(id: Fixtures.jobId, status: .queued))
        let second = await MainActor.run {
            UploadViewModel(
                palletService: secondPalletService, jobService: succeedingJobs,
                historyStore: store)
        }
        await MainActor.run {
            second.palletName = "Bin 12"
            second.setVideo(data: Data([0x00]), fileExtension: "mp4")
        }
        await second.startUpload()
        XCTAssertEqual(secondPalletService.created.count, 0)
        let secondState = await second.state
        XCTAssertEqual(secondState, .uploaded(jobId: Fixtures.jobId, palletId: Fixtures.palletId))
        suite.removePersistentDomain(forName: "PalletPilotPendingAdoptTests")
    }

    func testUploadViewModelIgnoresStalePending() async throws {
        let suite = UserDefaults(suiteName: "PalletPilotPendingStaleTests")!
        suite.removePersistentDomain(forName: "PalletPilotPendingStaleTests")
        let store = PalletHistoryStore(defaults: suite)
        store.savePending(PendingUpload(
            palletId: "old-pallet", name: "Old name", purchase: 1, additional: 0))
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        let jobService = FakeJobService()
        jobService.uploadResult = .success(JobCreated(id: Fixtures.jobId, status: .queued))
        let viewModel = await MainActor.run {
            UploadViewModel(
                palletService: palletService, jobService: jobService,
                historyStore: store)
        }
        await MainActor.run {
            viewModel.palletName = "Bin 12"
            viewModel.setVideo(data: Data([0x00]), fileExtension: "mp4")
        }
        await viewModel.startUpload()
        XCTAssertEqual(palletService.created.count, 1)
        suite.removePersistentDomain(forName: "PalletPilotPendingStaleTests")
    }

    func testExportFetchFailsClosedOnMissingReviewColumn() async throws {
        let csv = "item_id,title\n" + "a1,Drill\n"
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let service = FakePalletService(result: .success(pallet))
        service.exportResult = .success(Data(csv.utf8))
        let viewModel = await MainActor.run {
            ExportViewModel(palletId: Fixtures.palletId, palletService: service)
        }
        await viewModel.fetchCSV()
        let error = await viewModel.shareError
        XCTAssertNotNil(error)
        let data = await viewModel.csvData
        XCTAssertNil(data)
    }

    func testExportFetchFailureClearsStaleCSV() async throws {
        let csv = """
            item_id,title,description,category,brand,condition,suggested_price,currency,image_url,review_status
            a1,Drill,,Power Tools,Acme,good,45.0,USD,/f/1.jpg,approved
            """ + "\n"
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let service = FakePalletService(result: .success(pallet))
        service.exportResult = .success(Data(csv.utf8))
        let viewModel = await MainActor.run {
            ExportViewModel(palletId: Fixtures.palletId, palletService: service)
        }
        await viewModel.fetchCSV()
        let first = await viewModel.csvData
        XCTAssertNotNil(first)
        service.exportResult = .failure(APIError.http(statusCode: 500, detail: nil))
        await viewModel.fetchCSV()
        let second = await viewModel.csvData
        XCTAssertNil(second)
        let error = await viewModel.shareError
        XCTAssertNotNil(error)
    }

    func testItemDetailSaveRejectsInfiniteAndHugePrices() async throws {
        for bad in ["inf", "1e400", "100000000.01"] {
            let service = FakeItemService(item: try testDecoder().decode(
                Item.self, from: Data(Fixtures.itemPriced.utf8)))
            let viewModel = await MainActor.run {
                ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
            }
            await viewModel.load()
            await MainActor.run { viewModel.priceText = bad }
            await viewModel.save()
            let priceError = await viewModel.priceError
            XCTAssertNotNil(priceError, "price \(bad) should be rejected")
            XCTAssertTrue(service.patched.isEmpty)
        }
    }

    func testItemDetailSaveRejectsEmptyTitle() async throws {
        let service = FakeItemService(item: try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8)))
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
        }
        await viewModel.load()
        await MainActor.run {
            viewModel.title = "   "
            viewModel.priceText = "45"
        }
        await viewModel.save()
        let titleError = await viewModel.titleError
        XCTAssertNotNil(titleError)
        XCTAssertTrue(service.patched.isEmpty)
    }

    func testUploadViewModelSavesHistoryEntry() async throws {
        let suite = UserDefaults(suiteName: "PalletPilotUploadHistoryTests")!
        suite.removePersistentDomain(forName: "PalletPilotUploadHistoryTests")
        let store = PalletHistoryStore(defaults: suite)
        let pallet = try testDecoder().decode(Pallet.self, from: Data(Fixtures.pallet.utf8))
        let palletService = FakePalletService(result: .success(pallet))
        let jobService = FakeJobService()
        jobService.uploadResult = .success(JobCreated(id: Fixtures.jobId, status: .queued))
        let viewModel = await MainActor.run {
            UploadViewModel(
                palletService: palletService, jobService: jobService,
                historyStore: store)
        }
        await MainActor.run {
            viewModel.palletName = "Bin 12"
            viewModel.setVideo(data: Data([0x00]), fileExtension: "mp4")
        }
        await viewModel.startUpload()
        let saved = store.palletId(forJobId: Fixtures.jobId)
        XCTAssertEqual(saved, Fixtures.palletId)
        suite.removePersistentDomain(forName: "PalletPilotUploadHistoryTests")
    }

    func testItemDetailLabelsComeFromServer() async throws {
        let service = FakeItemService(item: try testDecoder().decode(
            Item.self, from: Data(Fixtures.itemPriced.utf8)))
        let viewModel = await MainActor.run {
            ItemDetailViewModel(itemId: "\(Fixtures.jobId):item_0", itemService: service)
        }
        await viewModel.load()
        let evidence = await viewModel.evidenceLine
        let source = await viewModel.priceSourceLabel
        let confidence = await viewModel.priceConfidenceLabel
        XCTAssertEqual(evidence, "mock identification: not verified against imagery")
        XCTAssertEqual(source, "Estimate · mock_fixture · asking")
        XCTAssertEqual(confidence, "Medium")
    }
}
