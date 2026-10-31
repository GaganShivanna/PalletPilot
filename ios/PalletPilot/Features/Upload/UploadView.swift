import PhotosUI
import SwiftUI

/// Upload flow (USER_FLOW.md Flow A): pallet details → video pick → create
/// pallet → upload → handoff to progress tracking. No inventory UI here.
struct UploadView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: UploadViewModel
    @State private var pickerItem: PhotosPickerItem?

    init(viewModel: UploadViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Pallet") {
                TextField("Name (optional)", text: $viewModel.palletName)
                TextField("Purchase cost", text: $viewModel.purchaseCostText)
                    .keyboardType(.decimalPad)
                TextField("Additional costs", text: $viewModel.additionalCostsText)
                    .keyboardType(.decimalPad)
            }

            Section("Video") {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Choose video", systemImage: "film")
                }
                .onChange(of: pickerItem) { _, item in
                    Task { await loadVideo(from: item) }
                }
                videoStatus
            }

            Section {
                uploadButton
                if case .failed(let message) = viewModel.state {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if case .uploaded(let jobId, let palletId) = viewModel.state {
                Section {
                    Button("Track progress") {
                        router.navigate(to: .processing(jobId: jobId, palletId: palletId))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("New pallet")
    }

    @ViewBuilder
    private var videoStatus: some View {
        switch viewModel.state {
        case .videoReady(let filename):
            Label(filename, systemImage: "checkmark.circle").foregroundStyle(.green)
        case .creatingPallet:
            Label("Creating pallet…", systemImage: "hourglass")
        case .uploading:
            Label("Uploading video…", systemImage: "arrow.up.circle")
        case .uploaded:
            Label("Upload complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            EmptyView()
        case .idle:
            Text("No video selected").foregroundStyle(.secondary)
        }
    }

    private var uploadButton: some View {
        Button {
            Task { await viewModel.startUpload() }
        } label: {
            switch viewModel.state {
            case .creatingPallet, .uploading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed:
                Text("Retry upload").frame(maxWidth: .infinity)
            default:
                Text("Create pallet and upload").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canUpload)
    }

    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return
        }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mp4"
        viewModel.setVideo(data: data, fileExtension: ext)
    }
}
