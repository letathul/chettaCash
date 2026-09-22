import SwiftUI
import UIKit

/// The app's reserved colour tokens (§8.2).
///
/// Light values are the specification's, verbatim. **Dark values are derived, not
/// specified** — §8.2 gives a single light palette — so they are kept here in Swift
/// rather than in an asset catalog, where they stay visible and tunable in review.
///
/// Each token pairs a light and a dark value through `UIColor(dynamicProvider:)`.
/// SwiftUI has no programmatic equivalent for an adaptive colour outside an asset
/// catalog, which is the §2 carve-out for touching UIKit.
///
/// Never reuse a semantic token for anything else, especially not as a category
/// colour — those live in ``CategorySwatch``.
enum Palette {

    // MARK: - Semantic

    /// Primary action, links and selected states.
    ///
    /// Lightens in dark appearance so it stays legible as text and as a tint on a
    /// dark ground.
    static let brandPurple = adaptive(light: 0x7A2FC4, dark: 0xA472E8)
    /// Gradient partner for ``brandPurple`` when it is used as a tint.
    static let brandPurpleGradientEnd = adaptive(light: 0x9B4FE0, dark: 0xBE8BF2)

    /// Hero card gradient start.
    ///
    /// In light appearance this is §8.2's `brandPurple` exactly. In dark it moves the
    /// opposite way from ``brandPurple``, deepening rather than lightening: a hero
    /// card carries white text, and the lightened tint drops that pairing below a
    /// 3:1 contrast ratio.
    static let heroGradientStart = adaptive(light: 0x7A2FC4, dark: 0x5B2191)
    /// Hero card gradient end, §8.2's `brandPurpleGradientEnd` in light appearance.
    static let heroGradientEnd = adaptive(light: 0x9B4FE0, dark: 0x7C3FB8)
    /// Income, active status and the "cheaper" badge.
    static let positiveGreen = adaptive(light: 0x2E9E5B, dark: 0x4FC97E)
    /// Expense, destructive actions, validation errors and failure banners.
    static let negativeRed = adaptive(light: 0xE0393E, dark: 0xF2696D)
    /// ``negativeRed`` pinned to its light value, for use on a hero card.
    ///
    /// The hero gradient is dark in **both** appearances, so a chip sitting on it does
    /// not follow the system trait. The dark variant of ``negativeRed`` is lighter, and
    /// on a white capsule it falls below 4.5:1 — so this one does not adapt.
    static let negativeRedOnHero = Color(uiColor: UIColor(rgb: 0xE0393E, alpha: 1))
    /// Due soon, trial ending and card-type accents.
    static let attentionAmber = adaptive(light: 0xB15E0F, dark: 0xE8963C)

    // MARK: - Neutrals

    /// Primary text.
    static let textPrimary = adaptive(light: 0x1C1B1F, dark: 0xF2F0F5)
    /// Secondary text and inactive tab items.
    static let textSecondary = adaptive(light: 0x8A8792, dark: 0xA6A2B0)
    /// Placeholders and disabled hints.
    static let placeholder = adaptive(light: 0xB4B0BE, dark: 0x6E6A7A)
    /// Screen background.
    static let appBackground = adaptive(light: 0xF7F5FB, dark: 0x131218)
    /// Card surfaces, raised above ``appBackground``.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C1B22)
    /// Card borders.
    static let borderSubtle = adaptive(light: 0xECE7F5, dark: 0x2E2B38)
    /// Segmented control track.
    static let segmentTrack = adaptive(light: 0xEDEAF3, dark: 0x2A2732)
    /// The selected pill inside a segmented control.
    static let segmentSelected = adaptive(light: 0xFFFFFF, dark: 0x3B3747)
    /// "+ Add new" dashed borders.
    static let dashedAccent = adaptive(light: 0xC9AEEE, dark: 0x7E5FB4)
    /// An off toggle's track.
    static let toggleOff = adaptive(light: 0xE0DCE8, dark: 0x3A3645)

    // MARK: - Error banner

    /// Error banner background.
    static let errorBannerBackground = adaptive(light: 0xFDEAEA, dark: 0x3A1B1C)
    /// Error banner border.
    static let errorBannerBorder = adaptive(light: 0xF5C2C4, dark: 0x6E2E30)
    /// Error banner text.
    static let errorBannerText = adaptive(light: 0xB0292E, dark: 0xF2888B)

    // MARK: - Attention banner

    /// Attention banner background. Amber rather than red: something needs doing, but
    /// nothing has gone wrong.
    static let attentionBannerBackground = adaptive(light: 0xFDF3E4, dark: 0x3A2B16)
    /// Attention banner border.
    static let attentionBannerBorder = adaptive(light: 0xF0D6A8, dark: 0x6E5227)
    /// Attention banner text.
    static let attentionBannerText = adaptive(light: 0x8A4A0B, dark: 0xE8B77C)

    // MARK: - Elevation

    /// Card shadow colour. Shadows barely read on a dark ground, so the dark value
    /// is stronger and the border carries more of the separation.
    static let cardShadow = adaptive(light: 0x1E0A32, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.4)

    /// Builds a colour that resolves differently in light and dark appearance.
    /// - Parameters:
    ///   - light: Packed `0xRRGGBB` value used in light appearance.
    ///   - dark: Packed `0xRRGGBB` value used in dark appearance.
    ///   - lightAlpha: Opacity in light appearance.
    ///   - darkAlpha: Opacity in dark appearance.
    /// - Returns: The adaptive colour.
    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    /// Builds a colour from a packed `0xRRGGBB` value.
    /// - Parameters:
    ///   - rgb: The packed colour components.
    ///   - alpha: The opacity to apply.
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
