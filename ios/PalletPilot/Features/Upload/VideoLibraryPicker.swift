import Photos
import SwiftUI

/// Library sheet for `UploadView`: a thumbnail grid where tapping a video
/// only checks it; the Select button confirms. Reports the checked video's
/// bytes through `onSelect` for the existing upload flow.
struct VideoLibraryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pickerModel = VideoPickerViewModel()
    @State private var errorMessage: String?
    let onSelect: (Data, String) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch pickerModel.status {
                case .loading:
                    ProgressView("Loading videos…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    deniedView
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .padding()
                case .ready:
                    if pickerModel.assets.isEmpty {
                        emptyView
                    } else {
                        gridView
                    }
                }
            }
            .navigationTitle("Choose video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if pickerModel.status == .ready, !pickerModel.assets.isEmpty {
                    selectBar
                }
            }
        }
        .task { await pickerModel.load() }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                Color.clear
                    .frame(height: 8)
                    .gridCellColumns(3)
                ForEach(pickerModel.assets, id: \.localIdentifier) { asset in
                    Button {
                        pickerModel.toggle(asset)
                    } label: {
                        VideoThumbnail(asset: asset)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .overlay(alignment: .topTrailing) {
                                checkmark(checked: pickerModel.selectedId == asset.localIdentifier)
                                    .padding(6)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Text(durationLabel(asset.duration))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6), in: Capsule())
                                    .padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func checkmark(checked: Bool) -> some View {
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(checked ? AppTheme.primary : .white)
            .background(checked ? Color.white : Color.clear, in: Circle())
            .shadow(radius: 2)
    }

    private var selectBar: some View {
        VStack(spacing: 6) {
            if pickerModel.selectedId == nil {
                Text("Tap a video to check it, then Select.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            PrimaryButton(title: "Select video", enabled: pickerModel.selectedId != nil) {
                Task {
                    do {
                        let (data, ext) = try await pickerModel.loadSelectedData()
                        onSelect(data, ext)
                        dismiss()
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Photo access is off")
                .font(.headline)
            Text("Allow access in Settings to browse your videos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No videos found")
                .font(.headline)
            Text("Save a clip to your photo library first, then come back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Async thumbnail for one library asset. The color box fixes the square
/// cell and the overlay image fills it edge to edge (portrait clips crop
/// top/bottom by design); no GeometryReader, which mis-sizes inside lazy
/// grids and leaves the fit/fill bands seen in review.
private struct VideoThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Color(.systemGray5)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task { await load() }
    }

    private func load() async {
        let options = PHImageRequestOptions()
        // Single delivery: `.opportunistic` invokes the result handler
        // multiple times, which would resume the continuation twice and
        // crash. High-quality format delivers exactly once.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let result: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        await MainActor.run { image = result }
    }
}
