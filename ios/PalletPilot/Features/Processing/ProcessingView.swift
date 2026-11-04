import SwiftUI

/// Processing status (USER_FLOW.md Flow A step 3): animated pipeline progress
/// with terminal failure guidance and completion handoff. The radar, scan
/// bar, and stage pulse are view-local loops; all truth comes from the view
/// model. Matches the app's grouped-background + card style.
struct ProcessingView: View {
    @Environment(\.router) private var router
    @StateObject private var viewModel: ProcessingViewModel
    @State private var pulse = false
    @State private var scan = false
    @State private var showDone = false
    private let palletId: String?

    init(viewModel: ProcessingViewModel, palletId: String?) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.palletId = palletId
    }

    var body: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    switch viewModel.state {
                    case .polling(let status, let frameCount):
                        radarCard(status: status, frameCount: frameCount)
                        timelineCard(current: status)
                        Text("You can leave this screen — the pallet keeps its results.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    case .completed(let job):
                        doneCard(job: job)
                    case .failed(let message):
                        failedCard(message: message)
                    case .timedOut:
                        timedOutCard
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.3), value: cardKey)
            }
        }
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.startLive()
            withAnimation {
                pulse = true
                scan = true
            }
        }
        .onDisappear { viewModel.stop() }
    }

    private var cardKey: String {
        switch viewModel.state {
        case .polling(let status, _): return "polling-\(status.rawValue)"
        case .completed: return "completed"
        case .failed: return "failed"
        case .timedOut: return "timedOut"
        }
    }

    // MARK: - Polling

    private func radarCard(status: JobStatus, frameCount: Int) -> some View {
        VStack(spacing: 12) {
            radar
            Text(statusLabel(status))
                .font(.title2.bold())
            if frameCount > 0 {
                Text("\(frameCount) frames sampled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            scanBar
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    /// Pulsing concentric radar rings around a viewfinder glyph.
    private var radar: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        AppTheme.primary.opacity(0.55 - Double(ring) * 0.15),
                        lineWidth: 2)
                    .frame(width: 64 + CGFloat(ring) * 30, height: 64 + CGFloat(ring) * 30)
                    .scaleEffect(pulse ? 1.1 : 0.92)
                    .opacity(pulse ? 0.45 : 1)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                            .delay(Double(ring) * 0.2),
                        value: pulse)
            }
            Image(systemName: "viewfinder")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .scaleEffect(pulse ? 1.06 : 0.96)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: pulse)
        }
        .frame(height: 160)
    }

    /// Indeterminate sliding scan bar.
    private var scanBar: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [AppTheme.primary.opacity(0.3), AppTheme.primary],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: 90, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .offset(x: scan ? proxy.size.width - 90 : 0)
                        .animation(
                            .linear(duration: 1.3).repeatForever(autoreverses: false),
                            value: scan)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 8)
    }

    private func timelineCard(current: JobStatus) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(timelineStages.enumerated()), id: \.element) { index, stage in
                stageRow(stage: stage, current: current)
                if index < timelineStages.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .padding(.vertical, 4)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private func stageRow(stage: JobStatus, current: JobStatus) -> some View {
        let order = JobStatus.allCases
        let stageIndex = order.firstIndex(of: stage) ?? 0
        let currentIndex = order.firstIndex(of: current) ?? 0
        return HStack(spacing: 12) {
            ZStack {
                if stageIndex < currentIndex {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else if stageIndex == currentIndex {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 12, height: 12)
                        .opacity(pulse ? 0.35 : 1)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: pulse)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(Color(.systemGray3))
                }
            }
            .frame(width: 28)
            Text(statusLabel(stage))
                .font(stageIndex == currentIndex ? .body.bold() : .body)
                .foregroundStyle(stageIndex <= currentIndex ? Color.primary : Color.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Terminal states

    private func doneCard(job: Job) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .scaleEffect(showDone ? 1 : 0.4)
                .opacity(showDone ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        showDone = true
                    }
                }
            Text("Analysis complete")
                .font(.title2.bold())
            Text("\(job.frameCount) frames · \(job.listings.count) draft listings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Drafts are estimates and need review — open the inventory to check each item.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let palletId {
                PrimaryButton(title: "View inventory") {
                    router.navigate(to: .inventory(palletId: palletId))
                }
                Button("Live scan") {
                    router.navigate(to: .capture(palletId: palletId, jobId: job.id))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private func failedCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("Processing failed")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Text("There is no re-run endpoint — upload the video again to retry.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Upload again") {
                router.popToRoot()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    private var timedOutCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.primary)
            Text("Still processing")
                .font(.title2.bold())
            Text("The job did not finish within 60 seconds. You can go back and check its pallet later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Back to Home") {
                router.popToRoot()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.horizontal, 16)
    }

    // MARK: - Labels

    private var timelineStages: [JobStatus] {
        [.queued, .samplingFrames, .segmenting, .identifying, .generatingPhotos, .generatingListings]
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
}
