import Foundation
import Photos

/// Photo-library video browser state: check one video, then confirm with an
/// explicit Select button. Uses PhotoKit directly (instead of the one-tap
/// `PhotosPicker`) so tapping a thumbnail only checks it — nothing is
/// selected until Select is tapped.
///
/// Requires `NSPhotoLibraryUsageDescription` in `Info.plist`.
@MainActor
final class VideoPickerViewModel: ObservableObject {
    enum Status: Equatable {
        case loading
        case ready
        case denied
        case failed(message: String)
    }

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status: Status = .loading
    @Published var selectedId: String?

    func load() async {
        status = .loading
        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard auth == .authorized || auth == .limited else {
            status = .denied
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var found: [PHAsset] = []
        found.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in found.append(asset) }
        assets = found
        status = .ready
    }

    func toggle(_ asset: PHAsset) {
        selectedId = (selectedId == asset.localIdentifier) ? nil : asset.localIdentifier
    }

    var selectedAsset: PHAsset? {
        guard let selectedId else { return nil }
        return assets.first { $0.localIdentifier == selectedId }
    }

    /// Full file data for the checked video. Matches what `UploadViewModel`
    /// expects: raw bytes plus the file extension for backend validation.
    func loadSelectedData() async throws -> (Data, String) {
        guard let asset = selectedAsset else {
            throw VideoPickerError.noSelection
        }
        let manager = PHImageManager.default()
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        guard let urlAsset = avAsset as? AVURLAsset else {
            throw VideoPickerError.unreadable
        }
        let ext = urlAsset.url.pathExtension.lowercased()
        let data = try Data(contentsOf: urlAsset.url)
        return (data, ext.isEmpty ? "mp4" : ext)
    }
}

enum VideoPickerError: LocalizedError {
    case noSelection
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noSelection: return "Check one video first."
        case .unreadable: return "Couldn't read that video file."
        }
    }
}
