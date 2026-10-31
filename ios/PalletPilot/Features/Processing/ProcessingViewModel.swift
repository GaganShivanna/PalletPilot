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
    private var task: Task<Void, Never>?

    init(
        jobService: JobServiceProtocol,
        jobId: String,
        pollInterval: TimeInterval = 1.0,
        timeout: TimeInterval = 60.0
    ) {
        self.jobService = jobService
        self.jobId = jobId
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.state = .polling(status: .queued, frameCount: 0)
    }

    convenience init(container: AppContainer, jobId: String) {
        self.init(jobService: container.jobService, jobId: jobId)
    }

    func start() {
        task?.cancel()
        task = Task { await poll() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        let deadline = Date().addingTimeInterval(timeout)
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
