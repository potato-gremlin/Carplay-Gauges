import ActivityKit
import SwiftUI
import WidgetKit

/// Renders the Live Activity: Lock Screen banner, Dynamic Island, and (automatically,
/// with no extra code) the CarPlay dashboard card on iOS 18+ when the phone is connected.
struct GaugesLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GaugeActivityAttributes.self) { context in
            GaugeActivityBannerView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let slot = context.state.slots.first {
                        SlotMiniView(slot: slot, style: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.slots.count > 1 {
                        SlotMiniView(slot: context.state.slots[1], style: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        ForEach(context.state.slots.dropFirst(2)) { slot in
                            SlotMiniView(slot: slot, style: .expanded)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(Color.accentColor)
            } compactTrailing: {
                if let slot = context.state.slots.first {
                    Text(slot.valueText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(slot.zone.color)
                }
            } minimal: {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct GaugeActivityBannerView: View {
    let state: GaugeActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(state.slots) { slot in
                SlotMiniView(slot: slot, style: .banner)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(state.isConnected ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
                .padding(8)
        }
    }
}

private struct SlotMiniView: View {
    enum Style { case banner, expanded }
    let slot: GaugeLiveSlot
    let style: Style

    var body: some View {
        VStack(spacing: 2) {
            Text(slot.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(slot.valueText)
                .font(.system(size: style == .banner ? 22 : 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(slot.zone.color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(slot.unit)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
