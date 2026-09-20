import SwiftUI

struct SettingsView: View {
    let layoutStore: GaugeLayoutStore
    let store: VehicleDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingDevicePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Demo Mode", isOn: Binding(
                        get: { store.isDemoMode },
                        set: { isOn in isOn ? store.enableDemoMode() : store.enableLiveMode() }
                    ))
                    if !store.isDemoMode {
                        Button("Connect Adapter\u{2026}") { showingDevicePicker = true }
                        if store.connectionState != .disconnected {
                            Button("Disconnect", role: .destructive) { store.disconnectFromDevice() }
                        }
                    }
                } header: {
                    Text("Data Source")
                } footer: {
                    Text("Demo Mode plays back simulated engine data so you can try the app without hardware.")
                }

                Section("Gauges") {
                    NavigationLink("Customize Gauges") {
                        GaugeEditorView(layoutStore: layoutStore, store: store)
                    }
                    Picker("Units", selection: Binding(
                        get: { layoutStore.layout.unitSystem },
                        set: { newValue in
                            layoutStore.layout.unitSystem = newValue
                        }
                    )) {
                        Text("Imperial (mph, \u{00B0}F)").tag(UnitSystem.imperial)
                        Text("Metric (km/h, \u{00B0}C)").tag(UnitSystem.metric)
                    }
                    Button("Reset Peak Values") { store.resetPeaks() }
                }

                Section {
                    Toggle("Show on Lock Screen & CarPlay", isOn: Binding(
                        get: { store.isLiveActivityEnabled },
                        set: { store.setLiveActivityEnabled($0) }
                    ))
                } header: {
                    Text("Live Activity")
                } footer: {
                    Text("Shows up to 4 gauges on your Lock Screen, Dynamic Island, and the CarPlay dashboard while connected or in Demo Mode.")
                }

                Section {
                    Button("Reset Layout to Default", role: .destructive) {
                        layoutStore.resetToDefault()
                        store.applyLayoutChange()
                    }
                }

                Section {
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(log: store.diagnosticsLog)
                    }
                } footer: {
                    Text("A raw trace of every command sent to the adapter and every response received \u{2014} useful for troubleshooting a connection that won't show live data.")
                }

                Section("About") {
                    LabeledContent("Vehicle", value: "2015 Ford Mustang")
                    LabeledContent("Adapter", value: "Generic ELM327 BLE (e.g. DA100)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingDevicePicker) {
                DevicePickerView(store: store)
            }
        }
    }
}
