import Foundation

/// Generates plausible fake readings on the same cadence real polling would, so every
/// screen can be exercised (and previewed) without hardware. Feeds "map" and "baro" like
/// a real session would so the derived "boost" gauge still works in demo mode.
final class DemoEngine {
    var onReading: ((_ pidID: String, _ value: Double) -> Void)?

    private var timer: Timer?
    private var t: Double = 0
    private var tick: Int = 0
    private var pids: [OBDPID] = []

    private static let tickInterval: TimeInterval = 0.2

    func start(pids: [OBDPID]) {
        self.pids = pids
        stop()
        t = 0
        tick = 0
        let timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.advance()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateActivePIDs(_ pids: [OBDPID]) {
        self.pids = pids
    }

    private func advance() {
        t += Self.tickInterval
        tick += 1
        let spike = (tick % 20 == 0)
        for pid in pids where !pid.isDerived {
            onReading?(pid.id, value(for: pid.id, spike: spike))
        }
    }

    private func value(for pidID: String, spike: Bool) -> Double {
        switch pidID {
        case "rpm":
            let cruise = 1400 + 1100 * sin(t / 3.4)
            let noise = Double.random(in: -40...40)
            return max(700, cruise + noise + (spike ? 2200 : 0))
        case "speed":
            return max(0, 48 + 40 * sin(t / 9.0))
        case "coolant_temp":
            return min(91, 18 + t * 1.4) + Double.random(in: -0.5...0.5)
        case "oil_temp":
            return min(102, 15 + t * 1.1) + Double.random(in: -0.5...0.5)
        case "intake_air_temp":
            return 26 + 3 * sin(t / 20.0)
        case "ambient_air_temp":
            return 22 + Double.random(in: -0.5...0.5)
        case "maf":
            return max(2, 25 + 20 * sin(t / 3.4) + (spike ? 35 : 0))
        case "throttle_pos":
            return max(0, min(100, 22 + 20 * sin(t / 3.4) + (spike ? 55 : 0)))
        case "engine_load":
            return max(5, min(100, 30 + 22 * sin(t / 3.4) + (spike ? 40 : 0)))
        case "map":
            return max(20, min(101, 35 + 15 * sin(t / 3.4) + (spike ? 20 : 0)))
        case "baro":
            return 99 + Double.random(in: -0.3...0.3)
        case "timing_advance":
            return 14 + 10 * sin(t / 3.4)
        case "fuel_level":
            return max(0, 68 - t / 120.0)
        case "module_voltage":
            return 14.2 + Double.random(in: -0.15...0.15)
        case "fuel_pressure":
            return 350 + Double.random(in: -8...8)
        case "run_time":
            return t
        default:
            return 0
        }
    }
}
