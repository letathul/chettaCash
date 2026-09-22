import SwiftUI

/// The app's type scale (§8.3, §12).
///
/// Every style is semantic, never a fixed `.system(size:)`, so the whole app tracks
/// Dynamic Type. The sizes quoted in §8.3 are the reference at the default text
/// size, not hard values.
enum Typography {
    /// Screen titles.
    static let screenTitle = Font.largeTitle.weight(.bold)
    /// Card headline numbers, such as Available Cash.
    static let headlineNumber = Font.title.weight(.semibold)
    /// A row's primary line, such as a merchant name.
    static let rowPrimary = Font.subheadline.weight(.semibold)
    /// A row's secondary line, such as "Category · Account".
    static let rowSecondary = Font.caption
    /// Validation captions beneath a field.
    static let errorCaption = Font.caption2
}

/// Renders text as an uppercase section label (§8.3).
private struct SectionLabelModifier: ViewModifier {
    /// The label's colour. Carried as a parameter because the modifier applies
    /// `foregroundStyle` closer to the text than any caller could, so an outer
    /// `foregroundStyle` would be overridden rather than applied.
    let color: Color

    /// Applies the section-label treatment.
    /// - Parameter content: The text to style.
    /// - Returns: The styled view.
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(color)
    }
}

/// Design-system text treatments (§8.3, §12).
extension View {
    /// Styles this text as an uppercase section label.
    /// - Parameter color: The label's colour. Pass `Palette.negativeRed` for the
    ///   invalid state of a form field (§7.11).
    /// - Returns: The styled view.
    func sectionLabel(color: Color = Palette.textSecondary) -> some View {
        modifier(SectionLabelModifier(color: color))
    }

    /// Styles this view as a currency figure.
    ///
    /// Uses `.monospacedDigit()` so amounts do not reflow while updating (§12).
    ///
    /// - Parameter font: The font to apply.
    /// - Returns: The styled view.
    func moneyText(_ font: Font = Typography.headlineNumber) -> some View {
        self.font(font.monospacedDigit())
    }
}
