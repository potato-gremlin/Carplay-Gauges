import SwiftUI

struct DevicePickerView: View {
    let store: VehicleDataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let warning = store.bluetoothWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    if store.discoveredPeripherals.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Scanning for adapters\u{2026}")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(store.discoveredPeripherals) { peripheral in
                        Button {
                            store.connect(to: peripheral.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peripheral.name)
                                        .foregroundStyle(.primary)
                                    Text("Signal: \(peripheral.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if peripheral.looksLikeOBDAdapter {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Nearby Bluetooth LE Devices")
                } footer: {
                    Text("Pick your ELM327-style OBD2 adapter. The app will probe it to find its serial characteristics automatically.")
                }
            }
            .navigationTitle("Connect Adapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.stopScanningForDevices()
                        dismiss()
                    }
                }
            }
            .onAppear { store.startScanningForDevices() }
            .onDisappear { store.stopScanningForDevices() }
        }
    }
}
