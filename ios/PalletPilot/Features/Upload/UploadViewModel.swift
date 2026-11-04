import Foundation

/// Upload flow state. The created pallet id is retained across retries so a
/// failed upload never creates a duplicate pallet (the backend has no pallet
/// delete); retry reuses it and uploads only.
enum UploadState: Equatable {
    case idle
    case videoReady(filename: String)
    case creatingPallet
    case uploading(palletName: String)
    case uploaded(jobId: String, palletId: String)
    case failed(message: String)
}

@MainActor
final class UploadViewModel: ObservableObject {
    @Published private(set) var state: UploadState = .idle
    @Published var palletName = ""
    @Published var purchaseCostText = ""
    @Published var additionalCostsText = ""

    private let palletService: PalletServiceProtocol
    private let jobService: JobServiceProtocol
    private let historyStore: PalletHistoryStore
    private var video: UploadVideo?
    private var createdPalletId: String?

    init(
        palletService: PalletServiceProtocol,
        jobService: JobServiceProtocol,
        historyStore: PalletHistoryStore = .init()
    ) {
        self.palletService = palletService
        self.jobService = jobService
        self.historyStore = historyStore
    }

    convenience init(container: AppContainer) {
        self.init(
            palletService: container.palletService,
            jobService: container.jobService,
            historyStore: container.palletHistoryStore)
    }

    var canUpload: Bool {
        if case .creatingPallet = state { return false }
        if case .uploading = state { return false }
        return video != nil
    }

    func setLoadFailure(_ message: String) {
        video = nil
        state = .failed(message: message)
    }

    func setVideo(data: Data, fileExtension: String) {
        do {
            video = try UploadVideo(data: data, fileExtension: fileExtension)
            if case .failed = state { state = .idle }
            state = .videoReady(filename: video?.filename ?? "video")
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    func startUpload() async {
        // The uploaded pallet already has a job: re-submitting would hit the
        // backend 409. The view replaces this button with Track progress.
        if case .uploaded = state { return }
        guard let video else {
            state = .failed(message: "Choose a video first.")
            return
        }
        guard let costs = validatedCosts() else { return }
        let draftName = palletName.isEmpty ? "Untitled pallet" : palletName
        do {
            let palletId: String
            if let createdPalletId {
                palletId = createdPalletId
            } else if let pending = historyStore.pendingUpload(),
                pending.name == draftName,
                pending.purchase == costs.purchase,
                pending.additional == costs.additional {
                // Same draft, new ViewModel (leave + return): adopt the
                // already-created pallet instead of duplicating it.
                createdPalletId = pending.palletId
                palletId = pending.palletId
            } else {
                state = .creatingPallet
                let pallet = try await palletService.createPallet(PalletCreate(
                    name: draftName,
                    purchaseCost: costs.purchase, additionalCosts: costs.additional
                ))
                createdPalletId = pallet.id
                palletId = pallet.id
                historyStore.save(palletId: pallet.id, jobId: nil, name: pallet.name)
                historyStore.savePending(PendingUpload(
                    palletId: pallet.id, name: draftName,
                    purchase: costs.purchase, additional: costs.additional))
            }
            state = .uploading(palletName: palletName)
            let created = try await jobService.uploadVideo(video, palletId: palletId)
            historyStore.save(
                palletId: palletId,
                jobId: created.id,
                name: draftName)
            historyStore.clearPending()
            state = .uploaded(jobId: created.id, palletId: palletId)
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }

    private func validatedCosts() -> (purchase: Double, additional: Double)? {
        let purchase = purchaseCostText.isEmpty ? 0 : Double(purchaseCostText)
        let additional = additionalCostsText.isEmpty ? 0 : Double(additionalCostsText)
        guard let purchase, let additional, purchase >= 0, additional >= 0 else {
            state = .failed(message: "Costs must be non-negative numbers.")
            return nil
        }
        return (purchase, additional)
    }
}
