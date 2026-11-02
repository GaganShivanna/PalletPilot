import SwiftUI

/// Capture screen (screenshots 0 ready + recording): full-screen camera
/// surface with dark translucent overlays. The preview is a placeholder
/// gradient (no camera entitlement in this target); Upload opens the
/// check-then-Select library flow, Items opens the pallet inventory, and the
/// record button runs a local timer.
struct CaptureView: View {
    @Environment(\.router) private var router
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CaptureViewModel
    private let palletId: String?

    init(viewModel: CaptureViewModel, palletId: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.palletId = palletId
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.85), AppTheme.captureBackground, Color.black.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack {
                Text("Live camera preview (full screen)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }
            VStack(spacing: 12) {
                topBar
                if viewModel.isRecording {
                    recordingOverlays
                } else {
                    instructionCard
                }
                Spacer()
                if viewModel.isRecording {
                    Text("\(viewModel.itemsFound) items found · tap to stop")
                        .font(.headline)
                        .foregroundStyle(.white)
                } else {
                    Text("Tap to record")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                bottomBar
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { viewModel.stopRecording() }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.capturePill, in: Circle())
                    .overlay(Circle().stroke(AppTheme.capturePillBorder, lineWidth: 1))
            }
            .accessibilityLabel("Close camera")
            Button {
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.palletName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(AppTheme.capturePill, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.capturePillBorder, lineWidth: 1))
            }
            Spacer()
            Button {
            } label: {
                Image(systemName: "bolt")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.capturePill, in: Circle())
                    .overlay(Circle().stroke(AppTheme.capturePillBorder, lineWidth: 1))
            }
        }
    }

    private var instructionCard: some View {
        VStack(spacing: 6) {
            Text("Scan your pallet")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Tap record, then hold each item up for 2–3 seconds before setting it aside.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(AppTheme.capturePill, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.capturePillBorder, lineWidth: 1))
        .padding(.horizontal, 8)
    }

    private var recordingOverlays: some View {
        VStack(spacing: 12) {
            if let item = viewModel.latestItem {
                HStack(spacing: 12) {
                    ItemThumbnail(size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LATEST ITEM · #\(viewModel.itemsFound)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(AppTheme.conditionLabel(item.condition)) · \(Int((item.confidence ?? 0) * 100))% sure")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Text(AppTheme.price(item.suggestedPrice))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .padding(12)
                .background(AppTheme.capturePill, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.capturePillBorder, lineWidth: 1))
            }
            HStack(spacing: 6) {
                Circle().fill(.white).frame(width: 8, height: 8)
                Text(viewModel.elapsedLabel)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.recordRed, in: Capsule())
            detectionBox
            Text("Hold each item steady for 2–3 seconds")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.capturePill, in: Capsule())
        }
    }

    private var detectionBox: some View {
        VStack(spacing: 0) {
            Text("Item \(viewModel.itemsFound + 1) · identifying…")
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.detectingBlue, in: Capsule())
                .padding(.bottom, 8)
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.detectingBlue, lineWidth: 4)
                .frame(width: 220, height: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.35))
                        .frame(width: 170, height: 170)
                )
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                router.navigate(to: .upload)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text("Upload")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 88, height: 76)
                .background(AppTheme.capturePill, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.capturePillBorder, lineWidth: 1))
            }
            Spacer()
            Button {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 88, height: 88)
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.recordRed)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(AppTheme.recordRed)
                            .frame(width: 68, height: 68)
                    }
                }
            }
            Spacer()
            Button {
                if let palletId {
                    router.navigate(to: .inventory(palletId: palletId))
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                    Text("Items")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 88, height: 76)
                .background(AppTheme.capturePill, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.capturePillBorder, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if viewModel.itemsFound > 0 {
                        Text("\(viewModel.itemsFound)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(AppTheme.primary, in: Circle())
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .disabled(palletId == nil)
        }
    }
}
