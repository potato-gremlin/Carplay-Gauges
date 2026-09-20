import SwiftUI

struct RootView: View {
    let layoutStore: GaugeLayoutStore
    let store: VehicleDataStore
    @State private var showingSettings = false
    @State private var showingDevicePicker = false

    var body: some View {
        ZStack(alignment: .top) {
            GaugesScreen(layoutStore: layoutStore, store: store)

            HStack(spacing: 10) {
                ConnectionStatusView(state: store.connectionState) {
                    if !store.isDemoMode { showingDevicePicker = true }
                }
                Spacer()
                Button {
                    store.resetPeaks()
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title2)
                }
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsView(layoutStore: layoutStore, store: store)
        }
        .sheet(isPresented: $showingDevicePicker) {
            DevicePickerView(store: store)
        }
    }
}
