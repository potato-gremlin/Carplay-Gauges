import Foundation
import Observation

/// A raw trace of every AT/OBD command sent and every response/timeout received. This
/// exists because nobody debugging this app has a way to see the device's console output —
/// the point is to let a user copy this out of the app and hand it over verbatim.
enum DiagnosticsDirection: String {
    case sent = "→"
    case received = "←"
    case info = "·"
    case error = "!"
}

struct DiagnosticsEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: DiagnosticsDirection
    let text: String
}

@Observable
final class DiagnosticsLog {
    private(set) var entries: [DiagnosticsEntry] = []
    private let maxEntries = 300

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func log(_ direction: DiagnosticsDirection, _ text: String) {
        entries.append(DiagnosticsEntry(timestamp: Date(), direction: direction, text: text))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var exportText: String {
        entries.map { entry in
            let time = Self.timeFormatter.string(from: entry.timestamp)
            return "\(time) \(entry.direction.rawValue) \(entry.text)"
        }.joined(separator: "\n")
    }
}
