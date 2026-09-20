import SwiftUI

/// Multi-select (up to 4) picker for which gauges appear on the Lock Screen / Dynamic
/// Island / CarPlay dashboard Live Activity.
struct LiveActivityPickerView: View {
    let layoutStore: GaugeLayoutStore

    private var selected: [String] { layoutStore.layout.liveActivityPidIDs }

    var body: some View {
        List(OBDPIDCatalog.all) { pid in
            Button {
                toggle(pid.id)
            } label: {
                HStack {
                    Text(pid.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected.contains(pid.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .disabled(!selected.contains(pid.id) && !canPickMore)
        }
        .navigationTitle("Live Activity Gauges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(selected.count)/4")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canPickMore: Bool { selected.count < 4 }

    private func toggle(_ pidID: String) {
        var current = selected
        if let index = current.firstIndex(of: pidID) {
            current.remove(at: index)
        } else if current.count < 4 {
            current.append(pidID)
        }
        layoutStore.setLiveActivitySlots(current)
    }
}
