import Foundation
import SwiftUI
import UIKit

/// Raw AT/OBD command trace. The point of this screen is purely to let someone copy it
/// out and hand it over — there's no way to see this device's console otherwise.
struct DiagnosticsView: View {
    let log: DiagnosticsLog
    @State private var didCopy = false

    var body: some View {
        List(log.entries) { entry in
            HStack(alignment: .top, spacing: 8) {
                Text(entry.direction.rawValue)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(color(for: entry.direction))
                Text(entry.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .overlay {
            if log.entries.isEmpty {
                ContentUnavailableView("No Traffic Yet", systemImage: "waveform.path.ecg",
                                        description: Text("Connect to an adapter (or reconnect) and this will fill up with every command sent and response received."))
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = log.exportText
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(log.entries.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Clear", role: .destructive) { log.clear() }
                    .disabled(log.entries.isEmpty)
            }
        }
    }

    private func color(for direction: DiagnosticsDirection) -> Color {
        switch direction {
        case .sent: return .blue
        case .received: return .green
        case .info: return .secondary
        case .error: return .red
        }
    }
}
