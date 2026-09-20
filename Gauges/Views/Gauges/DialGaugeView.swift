import SwiftUI

/// A 270-degree analog-style dial: dark face, a color-zoned value arc, tick marks, and an
/// optional peak-hold marker — styled after classic OBD gauge apps like Dr. Prius.
struct DialGaugeView: View {
    let pid: OBDPID
    let reading: PIDReading?
    let unitSystem: UnitSystem
    let peakHoldEnabled: Bool
    var customWarningValue: Double? = nil
    var customDangerValue: Double? = nil

    /// Full sweep is 270 of 360 degrees; rotating the whole ring 135 degrees puts the gap
    /// at the bottom, matching a classic automotive dial.
    private let sweepFraction = 0.75
    private let baseRotation = 135.0

    private var rawValue: Double { reading?.value ?? pid.minValue }
    private var valueRange: Double { max(pid.maxValue - pid.minValue, 0.0001) }
    private var fraction: Double { ((rawValue - pid.minValue) / valueRange).clamped(to: 0...1) }
    private var peakFraction: Double { (((reading?.peak ?? pid.minValue) - pid.minValue) / valueRange).clamped(to: 0...1) }

    private var warningFraction: Double {
        if let custom = customWarningValue { return ((custom - pid.minValue) / valueRange).clamped(to: 0...1) }
        return pid.warningFraction ?? 1.0
    }
    private var dangerFraction: Double {
        if let custom = customDangerValue { return ((custom - pid.minValue) / valueRange).clamped(to: 0...1) }
        return pid.dangerFraction ?? 1.0
    }

    private var zone: GaugeZoneLevel {
        pid.zoneLevel(for: rawValue, customWarningValue: customWarningValue, customDangerValue: customDangerValue)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(Color(white: 0.07))

                ring(from: 0, to: sweepFraction, color: Color.white.opacity(0.10), lineWidth: size * 0.09)

                ring(from: 0, to: sweepFraction * warningFraction, color: .green.opacity(0.35), lineWidth: size * 0.09)
                ring(from: sweepFraction * warningFraction, to: sweepFraction * dangerFraction, color: .yellow.opacity(0.35), lineWidth: size * 0.09)
                ring(from: sweepFraction * dangerFraction, to: sweepFraction, color: .red.opacity(0.35), lineWidth: size * 0.09)

                ring(from: 0, to: sweepFraction * fraction, color: zone.color, lineWidth: size * 0.09, lineCap: .round)
                    .shadow(color: zone.color.opacity(0.7), radius: size * 0.02)
                    .animation(.easeOut(duration: 0.2), value: fraction)

                tickMarks(size: size)

                if peakHoldEnabled, reading != nil {
                    peakMarker(size: size)
                }

                readout(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// `from`/`to` are fractions (0...1) of a full circle, measured from the dial's own
    /// zero point (already rotated so 0 sits at the bottom-left gap edge).
    private func ring(from: Double, to: Double, color: Color, lineWidth: CGFloat, lineCap: CGLineCap = .butt) -> some View {
        Circle()
            .trim(from: CGFloat(from), to: CGFloat(max(from, to)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
            .rotationEffect(.degrees(baseRotation))
    }

    private func tickMarks(size: CGFloat) -> some View {
        ForEach(0...10, id: \.self) { i in
            let f = Double(i) / 10.0
            let major = i % 5 == 0
            Rectangle()
                .fill(Color.white.opacity(major ? 0.55 : 0.3))
                .frame(width: major ? 2.5 : 1.5, height: size * (major ? 0.10 : 0.05))
                .offset(y: -(size / 2 - size * (major ? 0.05 : 0.025)))
                .rotationEffect(.degrees(sweepFraction * 360 * f - baseRotation))
        }
    }

    private func peakMarker(size: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 3, height: size * 0.12)
            .offset(y: -(size / 2 - size * 0.045))
            .rotationEffect(.degrees(sweepFraction * 360 * peakFraction - baseRotation))
    }

    private func readout(size: CGFloat) -> some View {
        VStack(spacing: size * 0.01) {
            Text(pid.shortName.uppercased())
                .font(.system(size: size * 0.085, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(formattedGaugeValue(unitSystem.convert(rawValue, baseUnit: pid.baseUnit)))
                .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unitSystem.displayUnit(for: pid.baseUnit))
                .font(.system(size: size * 0.075))
                .foregroundStyle(.secondary)
            if peakHoldEnabled, let reading {
                Text("PEAK \(formattedGaugeValue(unitSystem.convert(reading.peak, baseUnit: pid.baseUnit)))")
                    .font(.system(size: size * 0.065, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.top, size * 0.02)
            }
        }
        .frame(width: size * 0.62)
    }
}
