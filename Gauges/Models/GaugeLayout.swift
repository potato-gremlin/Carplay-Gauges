import Foundation
import Observation

struct GaugeSlotConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pidID: String
    var peakHoldEnabled: Bool = false
    /// Overrides for the PID's default warning/danger fractions, expressed in base unit values.
    /// Nil means "use the catalog default".
    var customWarningValue: Double?
    var customDangerValue: Double?
}

struct GaugePageConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var slots: [GaugeSlotConfig]
    var columns: Int = 2
}

struct GaugeLayout: Codable {
    var pages: [GaugePageConfig]
    var liveActivityPidIDs: [String]
    var unitSystem: UnitSystem

    static var defaultLayout: GaugeLayout {
        GaugeLayout(
            pages: [
                GaugePageConfig(title: "Main", slots: OBDPIDCatalog.defaultPage1.map {
                    GaugeSlotConfig(pidID: $0, peakHoldEnabled: $0 == "rpm")
                }),
                GaugePageConfig(title: "More", slots: OBDPIDCatalog.defaultPage2.map {
                    GaugeSlotConfig(pidID: $0)
                }),
            ],
            liveActivityPidIDs: OBDPIDCatalog.defaultLiveActivitySlots,
            unitSystem: .imperial
        )
    }

    /// All PID ids referenced anywhere in the layout (pages + live activity), deduplicated.
    var allActivePidIDs: Set<String> {
        var ids = Set(liveActivityPidIDs)
        for page in pages {
            for slot in page.slots {
                ids.insert(slot.pidID)
            }
        }
        // Boost is derived from map+baro; pull those in automatically when boost is used.
        if ids.contains("boost") {
            ids.insert("map")
            ids.insert("baro")
        }
        return ids
    }
}

@Observable
final class GaugeLayoutStore {
    private static let storageKey = "com.potatogremlin.carplaygauges.layout.v1"

    var layout: GaugeLayout {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(GaugeLayout.self, from: data) {
            layout = decoded
        } else {
            layout = .defaultLayout
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func resetToDefault() {
        layout = .defaultLayout
    }

    func addPage() {
        layout.pages.append(GaugePageConfig(title: "Page \(layout.pages.count + 1)", slots: []))
    }

    func removePage(_ pageID: GaugePageConfig.ID) {
        layout.pages.removeAll { $0.id == pageID }
    }

    func addGauge(pidID: String, toPage pageID: GaugePageConfig.ID) {
        guard let index = layout.pages.firstIndex(where: { $0.id == pageID }) else { return }
        layout.pages[index].slots.append(GaugeSlotConfig(pidID: pidID))
    }

    func removeGauges(at offsets: IndexSet, fromPage pageID: GaugePageConfig.ID) {
        guard let index = layout.pages.firstIndex(where: { $0.id == pageID }) else { return }
        layout.pages[index].slots.remove(atOffsets: offsets)
    }

    func setPeakHold(_ enabled: Bool, forSlot slotID: GaugeSlotConfig.ID, inPage pageID: GaugePageConfig.ID) {
        guard let pageIndex = layout.pages.firstIndex(where: { $0.id == pageID }),
              let slotIndex = layout.pages[pageIndex].slots.firstIndex(where: { $0.id == slotID }) else { return }
        layout.pages[pageIndex].slots[slotIndex].peakHoldEnabled = enabled
    }

    func setLiveActivitySlots(_ pidIDs: [String]) {
        layout.liveActivityPidIDs = Array(pidIDs.prefix(4))
    }
}
