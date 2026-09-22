import SwiftUI
import UIKit

/// A background and foreground pair for a category avatar (§8.2).
struct CategorySwatch: Hashable {
    /// The avatar's fill.
    let background: Color
    /// The glyph or initial drawn on that fill.
    let foreground: Color
}

/// The category colour palette (§8.2).
///
/// These are for transaction and product categories only, never for status. User
/// created categories are assigned a swatch round-robin by creation order.
enum CategoryPalette {

    /// Swatches for the seeded categories, keyed by their lowercased label.
    private static let byLabel: [String: CategorySwatch] = [
        "groceries": swatch(light: (0xDEF3EF, 0x12806F), dark: (0x133A33, 0x5FD9BF)),
        "food & drink": swatch(light: (0xEAF1FB, 0x2F6FCC), dark: (0x16253D, 0x7FB2F5)),
        "transport": swatch(light: (0xE1F0FA, 0x1587C9), dark: (0x0F2E3F, 0x5FC4F2)),
        "shopping": swatch(light: (0xF3EDD7, 0x8A6D1B), dark: (0x362E15, 0xD9BC63)),
        "bills": swatch(light: (0xF1E7DC, 0x8B5E3C), dark: (0x322620, 0xD2A281)),
        "entertainment": swatch(light: (0xFBE7F1, 0xC23B7A), dark: (0x3A1C2A, 0xF383B4)),
        "subscription": swatch(light: (0xE8E8F9, 0x4F52C4), dark: (0x21214A, 0x9A9CF0))
    ]

    /// The rotation used for user-created categories, in palette order.
    private static let rotation: [CategorySwatch] = [
        "groceries", "food & drink", "transport", "shopping",
        "bills", "entertainment", "subscription"
    ].compactMap { byLabel[$0] }

    /// The swatch used for income rows.
    static let income = swatch(light: (0xE7F7EE, 0x2E9E5B), dark: (0x14301F, 0x63D693))

    /// Returns the swatch for a category.
    ///
    /// A seeded label gets its designated swatch; anything else is assigned one
    /// round-robin by creation order, so two user categories never collide until
    /// the palette wraps.
    ///
    /// - Parameters:
    ///   - label: The category's display text.
    ///   - creationIndex: The category's position in creation order.
    /// - Returns: The swatch to draw its avatar with.
    static func swatch(for label: String, creationIndex: Int) -> CategorySwatch {
        if let known = byLabel[label.lowercased()] { return known }
        guard !rotation.isEmpty else { return income }
        let index = abs(creationIndex) % rotation.count
        return rotation[index]
    }

    /// Builds a swatch from packed light and dark colour pairs.
    /// - Parameters:
    ///   - light: Background and foreground in light appearance.
    ///   - dark: Background and foreground in dark appearance.
    /// - Returns: The swatch.
    private static func swatch(
        light: (background: UInt32, foreground: UInt32),
        dark: (background: UInt32, foreground: UInt32)
    ) -> CategorySwatch {
        CategorySwatch(
            background: adaptive(light: light.background, dark: dark.background),
            foreground: adaptive(light: light.foreground, dark: dark.foreground)
        )
    }

    /// Builds a colour that resolves differently in light and dark appearance.
    /// - Parameters:
    ///   - light: Packed `0xRRGGBB` value for light appearance.
    ///   - dark: Packed `0xRRGGBB` value for dark appearance.
    /// - Returns: The adaptive colour.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
