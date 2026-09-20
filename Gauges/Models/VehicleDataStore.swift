import Foundation
import Observation

/// The single observable source of truth for the whole app. Owns the real BLE/ELM327
/// session and the demo engine, and forwards whichever is active into `readings` so views
/// never need to know which one is live.
@Observable
final class VehicleDataStore {
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var readings: [String: PIDReading] = [:]
    private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
    private(set) var isDemoMode = false
    var bluetoothWarning: String?
    var lastError: String?

    private(set) var isLiveActivityEnabled: Bool
    let diagnosticsLog = DiagnosticsLog()

    private static let liveActivityDefaultsKey = "com.potatogremlin.carplaygauges.liveActivityEnabled"

    private let session = ELM327Session()
    private let demo = DemoEngine()
    private let liveActivity = LiveActivityController()
    private let layoutStore: GaugeLayoutStore
    private var hasLaunched = false

    init(layoutStore: GaugeLayoutStore) {
        self.layoutStore = layoutStore
        self.isLiveActivityEnabled = UserDefaults.standard.object(forKey: Self.liveActivityDefaultsKey) as? Bool ?? true

        session.onStateChanged = { [weak self] state in self?.updateConnectionState(state) }
        session.onReading = { [weak self] pidID, value in self?.handle(pidID: pidID, value: value) }
        session.onDiscoveredPeripheral = { [weak self] peripheral in self?.handleDiscovered(peripheral) }
        session.onBluetoothUnavailable = { [weak self] message in self?.bluetoothWarning = message }
        session.onError = { [weak self] message in self?.lastError = message }
        session.onLog = { [weak self] direction, text in self?.diagnosticsLog.log(direction, text) }
        demo.onReading = { [weak self] pidID, value in self?.handle(pidID: pidID, value: value) }
    }

    // MARK: - Lifecycle

    /// Called once at app launch (including background BLE-restoration launches).
    func startForLaunch() {
        guard !hasLaunched else { return }
        hasLaunched = true
        applyLayoutChange()
        if isDemoMode {
            startDemo()
        } else if !session.autoReconnect() {
            updateConnectionState(.disconnected)
        }
    }

    func applyLayoutChange() {
        let pids = activePIDList()
        session.setActivePIDs(pids)
        demo.updateActivePIDs(pids)
    }

    func enableDemoMode() {
        session.disconnect()
        isDemoMode = true
        startDemo()
    }

    func enableLiveMode() {
        demo.stop()
        isDemoMode = false
        resetReadings()
        applyLayoutChange()
        if !session.autoReconnect() {
            updateConnectionState(.disconnected)
        }
    }

    func startScanningForDevices() {
        discoveredPeripherals.removeAll()
        session.startScanning()
    }

    func stopScanningForDevices() {
        session.stopScanning()
    }

    func connect(to id: UUID) {
        resetReadings()
        session.connect(to: id)
    }

    func disconnectFromDevice() {
        session.disconnect()
        updateConnectionState(.disconnected)
        liveActivity.stop()
    }

    func resetPeaks() {
        for key in readings.keys {
            readings[key]?.peak = readings[key]?.value ?? readings[key]?.peak ?? 0
        }
    }

    func setLiveActivityEnabled(_ enabled: Bool) {
        isLiveActivityEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.liveActivityDefaultsKey)
        if enabled {
            refreshLiveActivity(force: true)
        } else {
            liveActivity.stop()
        }
    }

    // MARK: - Private

    private func startDemo() {
        resetReadings()
        updateConnectionState(.demo)
        demo.start(pids: activePIDList())
    }

    private func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        if state == .disconnected {
            // Leave any existing Live Activity showing "disconnected" rather than tearing
            // it down, so a brief drop doesn't make it flicker off the lock screen/CarPlay.
            refreshLiveActivity()
        } else {
            refreshLiveActivity(force: true)
        }
    }

    private func refreshLiveActivity(force: Bool = false) {
        guard isLiveActivityEnabled else { return }
        if liveActivity.isRunning {
            liveActivity.update(layout: layoutStore.layout, store: self, force: force)
        } else if connectionState.isActive {
            liveActivity.start(layout: layoutStore.layout, store: self)
        }
    }

    private func activePIDList() -> [OBDPID] {
        layoutStore.layout.allActivePidIDs.compactMap { OBDPIDCatalog.byID[$0] }
    }

    private func resetReadings() {
        readings.removeAll()
    }

    private func handleDiscovered(_ peripheral: DiscoveredPeripheral) {
        if let index = discoveredPeripherals.firstIndex(where: { $0.id == peripheral.id }) {
            discoveredPeripherals[index] = peripheral
        } else {
            discoveredPeripherals.append(peripheral)
        }
        discoveredPeripherals.sort { lhs, rhs in
            if lhs.looksLikeOBDAdapter != rhs.looksLikeOBDAdapter { return lhs.looksLikeOBDAdapter }
            return lhs.rssi > rhs.rssi
        }
    }

    private func handle(pidID: String, value: Double) {
        let now = Date()
        let previousPeak = readings[pidID]?.peak
        let peak = previousPeak.map { max($0, value) } ?? value
        readings[pidID] = PIDReading(value: value, peak: peak, timestamp: now)

        if pidID == "map" || pidID == "baro" {
            updateDerivedBoost()
        }
        refreshLiveActivity()
    }

    private func updateDerivedBoost() {
        guard let map = readings["map"]?.value, let baro = readings["baro"]?.value else { return }
        let boost = map - baro
        let previousPeak = readings["boost"]?.peak
        let peak = previousPeak.map { max($0, boost) } ?? boost
        readings["boost"] = PIDReading(value: boost, peak: peak, timestamp: Date())
    }
}
