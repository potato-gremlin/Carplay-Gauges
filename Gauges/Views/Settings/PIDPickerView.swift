import SwiftUI

/// Single-selection PID picker used when adding a gauge to a page.
struct PIDPickerView: View {
    let excluding: Set<String>
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(OBDPIDCatalog.all.filter { !excluding.contains($0.id) }) { pid in
            Button {
                onSelect(pid.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pid.name)
                        .foregroundStyle(.primary)
                    Text(pid.isDerived ? "Calculated \u{2022} \(pid.baseUnit)" : "PID 0x\(String(pid.pid, radix: 16, uppercase: true)) \u{2022} \(pid.baseUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add Gauge")
        .navigationBarTitleDisplayMode(.inline)
    }
}
