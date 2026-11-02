import Foundation

/// Capture screen state. Recording is a local timer; the latest-item card is
/// populated from the active job's listings poll when a `jobId` is attached
/// (no live-identification endpoint exists — see INTEGRATION_GAPS.md G9).
@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var itemsFound = 0
    @Published private(set) var latestItem: Item?
    @Published var palletName = "New pallet"

    private let jobService: JobServiceProtocol?
    private let palletService: PalletServiceProtocol?
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?

    init(jobService: JobServiceProtocol? = nil, palletService: PalletServiceProtocol? = nil) {
        self.jobService = jobService
        self.palletService = palletService
    }

    convenience init(container: AppContainer) {
        self.init(jobService: container.jobService, palletService: container.palletService)
    }

    var elapsedLabel: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    func startRecording() {
        isRecording = true
        elapsedSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
    }

    func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
    }

    /// Attach a pallet/job after the upload flow so the recording card and
    /// Items badge reflect server truth.
    func attach(palletId: String, jobId: String) async {
        guard let palletService, let jobService else { return }
        do {
            async let itemsCall = palletService.listItems(palletId: palletId)
            async let summaryCall = palletService.getSummary(palletId: palletId)
            let (items, summary) = try await (itemsCall, summaryCall)
            itemsFound = items.count
            latestItem = items.last
            palletName = summary.pallet.name
            _ = jobId
            _ = jobService
        } catch {
            // Card stays hidden; the timer still works offline.
        }
    }
}
