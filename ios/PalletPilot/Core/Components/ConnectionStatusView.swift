import SwiftUI

/// Reusable connectivity row: backend base URL, current state, and a check button.
/// Used by Home today; reused by future features needing a connection gate.
struct ConnectionStatusView: View {
    let state: ConnectionState
    let baseURL: String
    let onCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend")
                .font(.headline)
            Text(baseURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                statusDot
                statusText
                Spacer()
                Button("Check connection", action: onCheck)
                    .buttonStyle(.bordered)
                    .disabled(state == .checking)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Backend connection: \(accessibilityStatus)")
    }

    @ViewBuilder
    private var statusDot: some View {
        switch state {
        case .idle:
            Circle().fill(.gray).frame(width: 10, height: 10)
        case .checking:
            ProgressView().frame(width: 10, height: 10)
        case .connected:
            Circle().fill(.green).frame(width: 10, height: 10)
        case .failed:
            Circle().fill(.red).frame(width: 10, height: 10)
        }
    }

    private var statusText: some View {
        Group {
            switch state {
            case .idle:
                Text("Not checked")
            case .checking:
                Text("Checking…")
            case .connected(let serverStatus):
                Text("Connected (\(serverStatus))")
            case .failed(let message):
                Text(message).lineLimit(2)
            }
        }
        .font(.subheadline)
    }

    private var accessibilityStatus: String {
        switch state {
        case .idle: return "not checked"
        case .checking: return "checking"
        case .connected: return "connected"
        case .failed(let message): return "failed: \(message)"
        }
    }
}
