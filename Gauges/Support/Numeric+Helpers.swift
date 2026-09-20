import Foundation

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

func formattedGaugeValue(_ value: Double) -> String {
    guard value.isFinite else { return "\u{2013}\u{2013}" }
    return abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
}
