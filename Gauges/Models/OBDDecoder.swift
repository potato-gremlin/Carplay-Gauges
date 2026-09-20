import Foundation

/// Pure SAE J1979 Mode 01 decoders. Input is the raw data bytes for a PID
/// response *after* the mode/PID echo bytes have been stripped (i.e. just A, B, C, D...).
enum OBDDecoder {
    static func decode(pidID: String, bytes: [UInt8]) -> Double? {
        guard !bytes.isEmpty else { return nil }
        let a = Double(bytes[0])
        let b = bytes.count > 1 ? Double(bytes[1]) : 0

        switch pidID {
        case "rpm": return ((a * 256) + b) / 4.0
        case "speed": return a
        case "coolant_temp", "intake_air_temp", "ambient_air_temp", "oil_temp":
            return a - 40
        case "maf": return ((a * 256) + b) / 100.0
        case "throttle_pos", "engine_load", "fuel_level": return a * 100.0 / 255.0
        case "map", "baro": return a
        case "timing_advance": return (a / 2.0) - 64.0
        case "module_voltage": return ((a * 256) + b) / 1000.0
        case "fuel_pressure": return a * 3.0
        case "run_time": return (a * 256) + b
        default: return nil
        }
    }
}

enum UnitSystem: String, CaseIterable, Codable, Hashable {
    case imperial
    case metric

    func displayUnit(for baseUnit: String) -> String {
        switch (self, baseUnit) {
        case (.imperial, "km/h"): return "mph"
        case (.imperial, "\u{00B0}C"): return "\u{00B0}F"
        case (.imperial, "kPa"): return "psi"
        default: return baseUnit
        }
    }

    func convert(_ value: Double, baseUnit: String) -> Double {
        switch (self, baseUnit) {
        case (.imperial, "km/h"): return value * 0.621371
        case (.imperial, "\u{00B0}C"): return value * 9.0 / 5.0 + 32.0
        case (.imperial, "kPa"): return value * 0.145038
        default: return value
        }
    }

    /// Converts a value already expressed in this system's display unit back to the base unit.
    func toBase(_ displayValue: Double, baseUnit: String) -> Double {
        switch (self, baseUnit) {
        case (.imperial, "km/h"): return displayValue / 0.621371
        case (.imperial, "\u{00B0}C"): return (displayValue - 32.0) * 5.0 / 9.0
        case (.imperial, "kPa"): return displayValue / 0.145038
        default: return displayValue
        }
    }
}
