import SwiftUI

/// Processing status (USER_FLOW.md Flow A step 3): the 8-state pipeline with
/// progress detail, terminal failure with retry guidance, and completion
/// handoff. Inventory browsing arrives in a later phase.
struct ProcessingView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: ProcessingViewModel
    private let palletId: String?

    init(viewModel: ProcessingViewModel, palletId: String?) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.palletId = palletId
    }

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .polling(let status, let frameCount):
                ProgressView()
                Text(statusLabel(status)).font(.headline)
                if frameCount > 0 {
                    Text("\(frameCount) frames sampled")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                statusTimeline(current: status)
            case .completed(let job):
                Label("Analysis complete", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green)
                Text("\(job.frameCount) frames · \(job.listings.count) draft listings")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Drafts are mock data and need review — inventory browsing arrives in a later phase.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Label("Processing failed", systemImage: "xmark.circle.fill")
                    .font(.headline).foregroundStyle(.red)
                Text(message).font(.subheadline).multilineTextAlignment(.center)
                Text("There is no re-run endpoint — upload the video again to retry.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Upload again") { router.popToRoot() }
                    .buttonStyle(.borderedProminent)
            case .timedOut:
                Label("Still processing", systemImage: "hourglass")
                    .font(.headline)
                Text("The job did not finish within 60 seconds. You can go back and check its pallet later.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Back to Home") { router.popToRoot() }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Processing")
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private func statusLabel(_ status: JobStatus) -> String {
        switch status {
        case .queued: return "Queued"
        case .samplingFrames: return "Sampling frames"
        case .segmenting: return "Detecting products"
        case .identifying: return "Identifying products"
        case .generatingPhotos: return "Generating photos"
        case .generatingListings: return "Drafting listings"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private func statusTimeline(current: JobStatus) -> some View {
        let stages: [JobStatus] = [.queued, .samplingFrames, .segmenting, .identifying,
                                   .generatingPhotos, .generatingListings]
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(stages, id: \.self) { stage in
                HStack {
                    Image(systemName: stageImage(stage, current: current))
                        .foregroundStyle(stage == current ? Color.accentColor : Color.secondary)
                    Text(statusLabel(stage)).font(.caption)
                }
            }
        }
    }

    private func stageImage(_ stage: JobStatus, current: JobStatus) -> String {
        let order = JobStatus.allCases
        guard let a = order.firstIndex(of: stage), let b = order.firstIndex(of: current) else {
            return "circle"
        }
        if a < b { return "checkmark.circle.fill" }
        if a == b { return "circle.dotted" }
        return "circle"
    }
}
