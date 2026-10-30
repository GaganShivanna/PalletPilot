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
    private var video: UploadVideo?
    private var createdPalletId: String?

    init(palletService: PalletServiceProtocol, jobService: JobServiceProtocol) {
        self.palletService = palletService
        self.jobService = jobService
    }

    convenience init(container: AppContainer) {
        self.init(palletService: container.palletService, jobService: container.jobService)
    }

    var canUpload: Bool {
        if case .creatingPallet = state { return false }
        if case .uploading = state { return false }
        return video != nil
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
        guard let video else {
            state = .failed(message: "Choose a video first.")
            return
        }
        guard let costs = validatedCosts() else { return }
        do {
            let palletId: String
            if let createdPalletId {
                palletId = createdPalletId
            } else {
                state = .creatingPallet
                let pallet = try await palletService.createPallet(PalletCreate(
                    name: palletName.isEmpty ? "Untitled pallet" : palletName,
                    purchaseCost: costs.purchase, additionalCosts: costs.additional
                ))
                createdPalletId = pallet.id
                palletId = pallet.id
            }
            state = .uploading(palletName: palletName)
            let created = try await jobService.uploadVideo(video, palletId: palletId)
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
