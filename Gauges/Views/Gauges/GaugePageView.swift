import SwiftUI

struct GaugePageView: View {
    let page: GaugePageConfig
    let store: VehicleDataStore
    let unitSystem: UnitSystem

    var body: some View {
        ScrollView {
            if page.slots.isEmpty {
                ContentUnavailableView("No Gauges on This Page", systemImage: "gauge.with.needle",
                                        description: Text("Add gauges from Settings \u{2192} Customize Gauges."))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(page.columns, 1)), spacing: 14) {
                    ForEach(page.slots) { slot in
                        if let pid = OBDPIDCatalog.byID[slot.pidID] {
                            DialGaugeView(
                                pid: pid,
                                reading: store.readings[slot.pidID],
                                unitSystem: unitSystem,
                                peakHoldEnabled: slot.peakHoldEnabled,
                                customWarningValue: slot.customWarningValue,
                                customDangerValue: slot.customDangerValue
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}
