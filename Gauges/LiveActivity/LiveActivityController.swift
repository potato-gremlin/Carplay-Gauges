import ActivityKit
import Foundation

/// Starts/updates/ends the Live Activity from the main app process. Updates are local only
/// (no push entitlement needed) — the app keeps them flowing while it has background
/// execution time via the `bluetooth-central` background mode. No CarPlay entitlement or
/// code is involved: since iOS 18, a running Live Activity is surfaced on the CarPlay
/// dashboard automatically.
final class LiveActivityController {
    private var activity: Activity<GaugeActivityAttributes>?
    private var lastUpdateDate = Date.distantPast
    private static let minUpdateInterval: TimeInterval = 1.0

    var isRunning: Bool { activity != nil }

    func start(layout: GaugeLayout, store: VehicleDataStore) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity {
            Task { await activity.update(ActivityContent(state: contentState(layout: layout, store: store), staleDate: nil)) }
            return
        }
        let content = ActivityContent(state: contentState(layout: layout, store: store), staleDate: nil)
        activity = try? Activity.request(attributes: GaugeActivityAttributes(), content: content, pushType: nil)
        lastUpdateDate = Date()
    }

    func update(layout: GaugeLayout, store: VehicleDataStore, force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastUpdateDate) >= Self.minUpdateInterval else { return }
        lastUpdateDate = now
        let content = ActivityContent(state: contentState(layout: layout, store: store), staleDate: nil)
        Task { await activity.update(content) }
    }

    func stop() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func contentState(layout: GaugeLayout, store: VehicleDataStore) -> GaugeActivityAttributes.ContentState {
        let slots: [GaugeLiveSlot] = layout.liveActivityPidIDs.compactMap { pidID in
            guard let pid = OBDPIDCatalog.byID[pidID] else { return nil }
            let unit = layout.unitSystem.displayUnit(for: pid.baseUnit)
            guard let reading = store.readings[pidID] else {
                return GaugeLiveSlot(pidID: pidID, label: pid.shortName, valueText: "\u{2013}\u{2013}", unit: unit, zone: .normal)
            }
            let displayValue = layout.unitSystem.convert(reading.value, baseUnit: pid.baseUnit)
            let zone = pid.zoneLevel(for: reading.value)
            return GaugeLiveSlot(pidID: pidID, label: pid.shortName, valueText: formattedGaugeValue(displayValue), unit: unit, zone: zone)
        }
        return GaugeActivityAttributes.ContentState(slots: slots, isConnected: store.connectionState.isActive, lastUpdated: Date())
    }
}
