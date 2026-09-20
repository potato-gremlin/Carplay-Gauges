import CoreBluetooth
import Foundation

struct DiscoveredPeripheral: Identifiable, Hashable {
    var id: UUID
    var name: String
    var rssi: Int
    var looksLikeOBDAdapter: Bool

    static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum BLEHeuristics {
    /// Common substrings seen in the advertised names of cheap ELM327 BLE clones.
    /// Used only to sort likely candidates first — discovery still shows every
    /// nearby peripheral since "Generic/DA100" adapters can advertise anything.
    static let nameHints = ["OBD", "ELM", "OBDII", "OBD2", "VLINK", "VLINKER", "ICAR",
                             "VEEPEAK", "SCAN", "DA100", "BT4", "OBDBLE", "VGATE"]

    static func looksLikeOBDAdapter(name: String) -> Bool {
        let upper = name.uppercased()
        return nameHints.contains { upper.contains($0) }
    }

    /// Services/characteristics tried first when probing a freshly connected peripheral,
    /// in priority order, purely as a latency optimization. Any other notify+write pair
    /// discovered generically is still tried afterwards, so unknown "Generic" adapters work too.
    static let knownServiceUUIDs: [CBUUID] = [
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART
        CBUUID(string: "FFF0"),                                  // Common cheap OBD/HM clones
        CBUUID(string: "FFE0"),                                  // HM-10/HM-19
        CBUUID(string: "18F0"),                                  // Vgate-style
    ]
}
