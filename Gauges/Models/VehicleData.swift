import Foundation

struct PIDReading: Hashable {
    var value: Double
    var peak: Double
    var timestamp: Date
}

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(name: String)
    case initializing
    case connected(name: String)
    case reconnecting(attempt: Int)
    case demo

    var isActive: Bool {
        switch self {
        case .connected, .demo: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning\u{2026}"
        case .connecting(let name): return "Connecting to \(name)\u{2026}"
        case .initializing: return "Initializing adapter\u{2026}"
        case .connected(let name): return name
        case .reconnecting(let attempt): return "Reconnecting (\(attempt))\u{2026}"
        case .demo: return "Demo Mode"
        }
    }
}
