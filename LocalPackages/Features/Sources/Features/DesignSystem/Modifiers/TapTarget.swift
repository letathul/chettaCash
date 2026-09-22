import SwiftUI

/// Tap-target helpers (§8.4).
///
/// SwiftUI hit-tests a `Button` against its *label*, not against the frame, padding or
/// background chained onto the `Button` itself, and not across a `Spacer`. A row whose
/// label is a bare `HStack` is therefore live only where glyphs are drawn, and a capsule
/// painted outside the `Button` is decorative. These modifiers state the intended touch
/// area explicitly at the call site.
extension View {

    /// Makes this view's whole laid-out area tappable, transparent gaps included.
    ///
    /// Apply *inside* a `Button`'s label, after its padding and background.
    /// - Returns: The view with an explicit rectangular hit shape.
    func tappableSurface() -> some View {
        contentShape(.rect)
    }

    /// Grows the hit area outward on every edge without costing any layout space.
    ///
    /// The outward padding enlarges the region, `contentShape` claims it, and the equal
    /// negative padding hands the space back, so the drawn glyph and the surrounding
    /// spacing are unchanged. Choose `inset` so that the drawn size plus twice the inset
    /// reaches the 44pt minimum.
    ///
    /// Overflowing areas can overlap, and in a stack the later sibling wins the tap, so
    /// controls closer together than `inset` need real space rather than this modifier.
    /// - Parameter inset: Points to grow the hit area on each edge. Defaults to 8.
    /// - Returns: The view with an enlarged hit area and its original footprint.
    func iconTapTarget(expandedBy inset: CGFloat = 8) -> some View {
        padding(inset)
            .contentShape(.rect)
            .padding(-inset)
    }
}
