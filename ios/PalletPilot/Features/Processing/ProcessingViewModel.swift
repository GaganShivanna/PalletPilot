import Foundation

/// Processing poll state for one job (`GET /jobs/{id}`).
enum ProcessingState: Equatable {
    case polling(status: JobStatus, frameCount: Int)
    case completed(job: Job)
    case failed(message: String)
    case timedOut
}

/// Polls until the job reaches a terminal status. Interval/timeout mirror the
/// server's guidance (every ~1 s, 60 s cap); both are injectable for tests.
@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published private(set) var state: ProcessingState

    private let jobService: JobServiceProtocol
    private let jobId: String
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval
    private let sseClient: SSEClientProtocol?
    private let baseURL: URL?
    private var task: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    init(
        jobService: JobServiceProtocol,
        jobId: String,
        pollInterval: TimeInterval = 1.0,
        timeout: TimeInterval = 60.0,
        sseClient: SSEClientProtocol? = nil,
        baseURL: URL? = nil
    ) {
        self.jobService = jobService
        self.jobId = jobId
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.sseClient = sseClient
        self.baseURL = baseURL
        self.state = .polling(status: .queued, frameCount: 0)
    }

    convenience init(container: AppContainer, jobId: String) {
        self.init(
            jobService: container.jobService,
            jobId: jobId,
            sseClient: SSEClient(),
            baseURL: container.configuration.baseURL)
    }

    func start() {
        stop()
        task = Task { await poll(until: Date().addingTimeInterval(timeout)) }
    }

    /// Live progress via `GET /jobs/{id}/events`, falling back to polling
    /// when events are unavailable (nil client) or the stream ends or fails
    /// before a terminal event.
    func startLive() {
        stop()
        eventTask = Task { await followEvents() }
    }

    func stop() {
        task?.cancel()
        task = nil
        eventTask?.cancel()
        eventTask = nil
    }

    private func eventsURL() -> URL? {
        guard let baseURL else { return nil }
        return URL(string: "/jobs/\(jobId)/events", relativeTo: baseURL)?.absoluteURL
    }

    private func followEvents() async {
        let deadline = Date().addingTimeInterval(timeout)
        guard let sseClient, let url = eventsURL() else {
            await poll(until: deadline)
            return
        }
        var seenIDs = Set<Int>()
        do {
            for try await frame in sseClient.events(url: url, lastEventID: nil) {
                if Task.isCancelled { return }
                if Date() >= deadline {
                    state = .timedOut
                    return
                }
                guard let payload = frame.data.data(using: .utf8),
                    let event = try? sseClient.decodeJobEvent(from: payload)
                else { continue }
                if !seenIDs.insert(event.id).inserted { continue }
                if event.isTerminal {
                    await finishFromServer()
                    return
                }
                await refreshSnapshot()
            }
            // Stream ended without a terminal event: keep polling.
            await poll(until: deadline)
        } catch {
            if Task.isCancelled { return }
            await poll(until: deadline)
        }
    }

    /// Terminal rendering always comes from a fresh `GET /jobs/{id}` so
    /// listings counts and errors match the server, never the event payload.
    private func finishFromServer() async {
        do {
            let job = try await jobService.getJob(id: jobId)
            state = job.status == .completed
                ? .completed(job: job)
                : .failed(message: job.error ?? "Processing failed.")
        } catch {
            if Task.isCancelled { return }
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    private func refreshSnapshot() async {
        guard let job = try? await jobService.getJob(id: jobId) else { return }
        if Task.isCancelled { return }
        if job.status.isTerminal {
            state = job.status == .completed
                ? .completed(job: job)
                : .failed(message: job.error ?? "Processing failed.")
        } else {
            state = .polling(status: job.status, frameCount: job.frameCount)
        }
    }

    private func poll(until deadline: Date) async {
        while !Task.isCancelled {
            do {
                let job = try await jobService.getJob(id: jobId)
                if job.status.isTerminal {
                    state = job.status == .completed
                        ? .completed(job: job)
                        : .failed(message: job.error ?? "Processing failed.")
                    return
                }
                state = .polling(status: job.status, frameCount: job.frameCount)
            } catch {
                if Task.isCancelled { return }
                state = .failed(message: (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription)
                return
            }
            if Date() >= deadline {
                state = .timedOut
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }
}
