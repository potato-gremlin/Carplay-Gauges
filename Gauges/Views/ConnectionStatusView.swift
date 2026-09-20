import SwiftUI

struct ConnectionStatusView: View {
    let state: ConnectionState
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(state.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var isBusy: Bool {
        switch state {
        case .scanning, .connecting, .initializing, .reconnecting: return true
        default: return false
        }
    }

    private var dotColor: Color {
        switch state {
        case .connected, .demo: return .green
        case .disconnected: return .gray
        case .reconnecting: return .orange
        case .scanning, .connecting, .initializing: return .yellow
        }
    }
}
