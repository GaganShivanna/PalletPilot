import AVFoundation
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

    /// Backend cap (`backend/app/config.py: max_upload_mb`, default 500).
    /// Checked before bytes are read so oversized clips fail fast instead of
    /// spiking upload memory.
    static let maxUploadBytes = 500 * 1024 * 1024

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
        let fileURL = urlAsset.url
        if let byteCount = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]
            as? NSNumber)?.intValue,
            byteCount > Self.maxUploadBytes {
            throw VideoPickerError.tooLarge(maxMB: Self.maxUploadBytes / 1024 / 1024)
        }
        let data = try Data(contentsOf: fileURL)
        if data.count > Self.maxUploadBytes {
            throw VideoPickerError.tooLarge(maxMB: Self.maxUploadBytes / 1024 / 1024)
        }
        let ext = fileURL.pathExtension.lowercased()
        return (data, ext.isEmpty ? "mp4" : ext)
    }
}

enum VideoPickerError: LocalizedError {
    case noSelection
    case unreadable
    case tooLarge(maxMB: Int)

    var errorDescription: String? {
        switch self {
        case .noSelection: return "Check one video first."
        case .unreadable: return "Couldn't read that video file."
        case .tooLarge(let maxMB): return "That video is over \(maxMB) MB — pick a shorter clip."
        }
    }
}
