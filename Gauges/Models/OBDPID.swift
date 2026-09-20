import Foundation

/// A single Mode 01 OBD-II PID we know how to request and render as a gauge.
/// Values are always normalized to metric SI-ish units here (C, kPa, km/h);
/// `UnitSystem` converts for display.
struct OBDPID: Identifiable, Hashable, Codable {
    let id: String
    let pid: UInt8
    let name: String
    let shortName: String
    /// Canonical (metric) unit produced by `OBDDecoder.decode`.
    let baseUnit: String
    let responseByteCount: Int
    let minValue: Double
    let maxValue: Double
    /// Fraction of range (0...1) where the gauge turns yellow / red. Nil disables that zone.
    let warningFraction: Double?
    let dangerFraction: Double?
    let supportsPeakHold: Bool
    let isDerived: Bool

    static func == (lhs: OBDPID, rhs: OBDPID) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Which color zone a raw (base-unit) value falls into, optionally with per-gauge
    /// threshold overrides (in base-unit values) in place of the catalog defaults.
    func zoneLevel(for rawValue: Double, customWarningValue: Double? = nil, customDangerValue: Double? = nil) -> GaugeZoneLevel {
        let range = maxValue - minValue
        let effectiveDanger = customDangerValue ?? dangerFraction.map { minValue + $0 * range }
        let effectiveWarning = customWarningValue ?? warningFraction.map { minValue + $0 * range }
        if let danger = effectiveDanger, rawValue >= danger { return .danger }
        if let warning = effectiveWarning, rawValue >= warning { return .warning }
        return .normal
    }
}

enum OBDPIDCatalog {
    /// Standard Mode 01 PIDs, useful across essentially any OBD-II gasoline vehicle
    /// (including a 2015 Ford Mustang V6/GT/EcoBoost). We deliberately avoid
    /// manufacturer-specific enhanced PIDs since those vary by trim/ECU and can't be
    /// verified generically.
    static let all: [OBDPID] = [
        OBDPID(id: "rpm", pid: 0x0C, name: "Engine RPM", shortName: "RPM",
               baseUnit: "rpm", responseByteCount: 2, minValue: 0, maxValue: 8000,
               warningFraction: 0.75, dangerFraction: 0.90, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "speed", pid: 0x0D, name: "Vehicle Speed", shortName: "Speed",
               baseUnit: "km/h", responseByteCount: 1, minValue: 0, maxValue: 240,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "coolant_temp", pid: 0x05, name: "Coolant Temp", shortName: "Coolant",
               baseUnit: "\u{00B0}C", responseByteCount: 1, minValue: -40, maxValue: 150,
               warningFraction: 0.72, dangerFraction: 0.85, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "intake_air_temp", pid: 0x0F, name: "Intake Air Temp", shortName: "IAT",
               baseUnit: "\u{00B0}C", responseByteCount: 1, minValue: -40, maxValue: 100,
               warningFraction: 0.8, dangerFraction: 0.93, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "ambient_air_temp", pid: 0x46, name: "Ambient Air Temp", shortName: "Ambient",
               baseUnit: "\u{00B0}C", responseByteCount: 1, minValue: -40, maxValue: 60,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "maf", pid: 0x10, name: "Mass Air Flow", shortName: "MAF",
               baseUnit: "g/s", responseByteCount: 2, minValue: 0, maxValue: 260,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "throttle_pos", pid: 0x11, name: "Throttle Position", shortName: "Throttle",
               baseUnit: "%", responseByteCount: 1, minValue: 0, maxValue: 100,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "engine_load", pid: 0x04, name: "Engine Load", shortName: "Load",
               baseUnit: "%", responseByteCount: 1, minValue: 0, maxValue: 100,
               warningFraction: 0.85, dangerFraction: 0.97, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "map", pid: 0x0B, name: "Intake Manifold Pressure", shortName: "MAP",
               baseUnit: "kPa", responseByteCount: 1, minValue: 0, maxValue: 255,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "baro", pid: 0x33, name: "Barometric Pressure", shortName: "Baro",
               baseUnit: "kPa", responseByteCount: 1, minValue: 60, maxValue: 110,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "timing_advance", pid: 0x0E, name: "Timing Advance", shortName: "Timing",
               baseUnit: "\u{00B0}", responseByteCount: 1, minValue: -64, maxValue: 63.5,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "fuel_level", pid: 0x2F, name: "Fuel Level", shortName: "Fuel",
               baseUnit: "%", responseByteCount: 1, minValue: 0, maxValue: 100,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "module_voltage", pid: 0x42, name: "Control Module Voltage", shortName: "Voltage",
               baseUnit: "V", responseByteCount: 2, minValue: 8, maxValue: 18,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "fuel_pressure", pid: 0x0A, name: "Fuel Pressure", shortName: "Fuel Psi",
               baseUnit: "kPa", responseByteCount: 1, minValue: 0, maxValue: 765,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        OBDPID(id: "oil_temp", pid: 0x5C, name: "Engine Oil Temp", shortName: "Oil Temp",
               baseUnit: "\u{00B0}C", responseByteCount: 1, minValue: -40, maxValue: 170,
               warningFraction: 0.75, dangerFraction: 0.9, supportsPeakHold: true, isDerived: false),

        OBDPID(id: "run_time", pid: 0x1F, name: "Run Time Since Start", shortName: "Run Time",
               baseUnit: "s", responseByteCount: 2, minValue: 0, maxValue: 3600,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: false, isDerived: false),

        // Derived (computed client-side from MAP - Baro). Useful on turbo trims (e.g. EcoBoost);
        // reads ~0 on naturally aspirated engines, which is still a valid vacuum/boost signal.
        OBDPID(id: "boost", pid: 0x00, name: "Boost / Vacuum", shortName: "Boost",
               baseUnit: "kPa", responseByteCount: 0, minValue: -50, maxValue: 150,
               warningFraction: nil, dangerFraction: nil, supportsPeakHold: true, isDerived: true),
    ]

    static let byID: [String: OBDPID] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let defaultPage1: [String] = ["rpm", "speed", "coolant_temp", "throttle_pos"]
    static let defaultPage2: [String] = ["engine_load", "intake_air_temp", "module_voltage", "fuel_level"]
    static let defaultLiveActivitySlots: [String] = ["rpm", "speed", "coolant_temp", "throttle_pos"]
}
