import ActivityKit
import SwiftUI
import WidgetKit

/// Renders the Live Activity: Lock Screen banner, Dynamic Island, and — by opting into the
/// `.small` supplemental activity family — the compact persistent banner CarPlay (and the
/// Apple Watch Smart Stack) actually render Live Activities in. No CarPlay entitlement
/// needed for this; that's a separate thing from building a full CarPlay app.
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
        .supplementalActivityFamilies([.small])
    }
}

private struct GaugeActivityBannerView: View {
    @Environment(\.activityFamily) private var activityFamily
    let state: GaugeActivityAttributes.ContentState

    var body: some View {
        switch activityFamily {
        case .small:
            GaugeActivityCompactView(state: state)
        default:
            GaugeActivityFullBannerView(state: state)
        }
    }
}

/// The default Lock Screen banner — plenty of room for all 4 gauges.
private struct GaugeActivityFullBannerView: View {
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

/// The `.small` family — what CarPlay's persistent banner and the Watch Smart Stack
/// actually render. Tight on space, so only the first two configured gauges, no sentences.
private struct GaugeActivityCompactView: View {
    let state: GaugeActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ForEach(state.slots.prefix(2)) { slot in
                VStack(spacing: 0) {
                    Text(slot.valueText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(slot.zone.color)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(slot.label) \(slot.unit)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
