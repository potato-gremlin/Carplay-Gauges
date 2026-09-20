import SwiftUI

struct GaugeEditorView: View {
    let layoutStore: GaugeLayoutStore
    let store: VehicleDataStore

    var body: some View {
        List {
            ForEach(layoutStore.layout.pages) { page in
                Section {
                    ForEach(page.slots) { slot in
                        if let pid = OBDPIDCatalog.byID[slot.pidID] {
                            HStack {
                                Text(pid.name)
                                Spacer()
                                Button {
                                    layoutStore.setPeakHold(!slot.peakHoldEnabled, forSlot: slot.id, inPage: page.id)
                                } label: {
                                    Image(systemName: slot.peakHoldEnabled ? "flag.fill" : "flag")
                                        .foregroundStyle(slot.peakHoldEnabled ? .orange : .secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(!pid.supportsPeakHold)
                                .opacity(pid.supportsPeakHold ? 1 : 0.3)
                            }
                        }
                    }
                    .onDelete { offsets in
                        layoutStore.removeGauges(at: offsets, fromPage: page.id)
                        store.applyLayoutChange()
                    }

                    NavigationLink("Add Gauge") {
                        PIDPickerView(excluding: Set(page.slots.map(\.pidID))) { pidID in
                            layoutStore.addGauge(pidID: pidID, toPage: page.id)
                            store.applyLayoutChange()
                        }
                    }
                } header: {
                    Text(page.title)
                } footer: {
                    if layoutStore.layout.pages.count > 1 {
                        Button("Delete Page", role: .destructive) {
                            layoutStore.removePage(page.id)
                            store.applyLayoutChange()
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                Button {
                    layoutStore.addPage()
                } label: {
                    Label("Add Page", systemImage: "plus.square")
                }
            }

            Section {
                ForEach(layoutStore.layout.liveActivityPidIDs, id: \.self) { pidID in
                    if let pid = OBDPIDCatalog.byID[pidID] {
                        Text(pid.name)
                    }
                }
                NavigationLink("Edit Live Activity Gauges") {
                    LiveActivityPickerView(layoutStore: layoutStore)
                }
            } header: {
                Text("Live Activity (up to 4)")
            } footer: {
                Text("These gauges appear on your Lock Screen, Dynamic Island, and CarPlay dashboard.")
            }
        }
        .navigationTitle("Customize Gauges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
