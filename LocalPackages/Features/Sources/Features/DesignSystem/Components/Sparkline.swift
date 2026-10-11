import SwiftUI

/// A single-stroke line chart of already-normalised values (§7.1).
///
/// Takes unit ratios rather than money, because ``Domain/BalanceSeries`` has already
/// worked out the band and where each point sits in it — including the flat case,
/// which arrives as a run of `0.5` rather than as a division by zero. A `Shape`
/// rather than a `View` so the caller owns the stroke's colour and weight, and so it
/// animates between series.
struct Sparkline: Shape {
    /// Each point's position in the band, `0` at the bottom and `1` at the top,
    /// oldest first.
    let values: [Double]

    /// Traces the line across the available width.
    /// - Parameter rect: The area to draw in.
    /// - Returns: The path, empty when there are fewer than two points to join.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let clamped = min(max(value, 0), 1)
            let point = CGPoint(
                x: rect.minX + CGFloat(index) * step,
                // SwiftUI's y grows downward, so the high value sits at the low y.
                y: rect.maxY - clamped * rect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
