import ActivityKit
import SwiftUI

/// Shared between the main app (which starts/updates the activity) and the
/// widget extension (which renders it). Compiled into both targets.
struct GaugeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var slots: [GaugeLiveSlot]
        var isConnected: Bool
        var lastUpdated: Date
    }
}

struct GaugeLiveSlot: Codable, Hashable, Identifiable {
    var id: String { pidID }
    var pidID: String
    var label: String
    var valueText: String
    var unit: String
    var zone: GaugeZoneLevel
}

enum GaugeZoneLevel: String, Codable, Hashable {
    case normal, warning, danger

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .danger: return .red
        }
    }
}
