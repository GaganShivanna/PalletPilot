import SwiftUI
import UniformTypeIdentifiers

/// Export screen (screenshot 8): file card, inclusion rows, and a share
/// button that downloads `GET /pallets/{id}/export` and presents a
/// `ShareLink` for the CSV file.
/// Identifiable wrapper so the share sheet can bind to the exported file.
private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExportView: View {
    @StateObject private var viewModel: ExportViewModel
    @State private var shareFile: ShareFile?

    init(viewModel: ExportViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fileCard
                    SectionHeader(text: "What's included")
                    includedCard
                    Text("Columns: title, description, condition, category, price, photo file names. Uses your latest edits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    PrimaryButton(title: "Share CSV") {
                        Task {
                            await viewModel.fetchCSV()
                            writeShareFile()
                        }
                    }
                    .padding(.horizontal, 16)
                    if let error = viewModel.shareError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }
                    Text("Opens the iOS share sheet: save to Files, AirDrop or email it to yourself.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(item: $shareFile) { file in
            ShareSheet(url: file.url)
        }
    }

    private var fileCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBlue).opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(viewModel.exportedCount) listings · spreadsheet-ready columns")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var includedCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reviewed items").font(.body)
                Spacer()
                Text("\(viewModel.reviewedCount)").font(.body)
            }
            .padding(12)
            Divider().padding(.leading, 16)
            HStack {
                Text("Include \(viewModel.unreviewedCount) unreviewed items").font(.body)
                Spacer()
                Toggle("", isOn: $viewModel.includeUnreviewed)
                    .labelsHidden()
            }
            .padding(12)
            Divider().padding(.leading, 16)
            HStack {
                Text("Donate or skip").font(.body)
                Spacer()
                Text("\(viewModel.donateCount)").font(.body)
            }
            .padding(12)
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private func writeShareFile() {
        guard let data = viewModel.csvData else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(viewModel.fileName)
        do {
            try data.write(to: url, options: .atomic)
            shareFile = ShareFile(url: url)
        } catch {
            viewModel.shareError = "Could not write CSV file: \(error.localizedDescription)"
        }
    }
}

/// UIKit share sheet for the exported CSV file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
