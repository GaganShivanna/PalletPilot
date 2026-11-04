import SwiftUI

/// Past-jobs screen (`GET /jobs`). Status and error come straight from the
/// server; a row opens the pallet inventory only when this device created
/// or claimed that pallet (otherwise there is nothing to open).
struct HistoryView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()
            switch viewModel.state {
            case .loading:
                ProgressView("Loading jobs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await viewModel.load() } }
                        .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if viewModel.jobs.isEmpty {
                    VStack(spacing: 8) {
                        Text("No jobs yet")
                            .font(.headline)
                        Text("Upload a video to start your first analysis.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.jobs) { job in
                        jobRow(job)
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("Past jobs")
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func jobRow(_ job: Job) -> some View {
        if let palletId = viewModel.palletId(for: job.id) {
            Button {
                router.navigate(to: .inventory(palletId: palletId))
            } label: {
                rowContent(job)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(job)
        }
    }

    private func rowContent(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.videoFilename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(job.status.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(job.status == .failed ? Color.red : AppTheme.primary)
            }
            HStack {
                Text("\(job.frameCount) frames")
                Text("·")
                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if job.status == .failed, let error = job.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
