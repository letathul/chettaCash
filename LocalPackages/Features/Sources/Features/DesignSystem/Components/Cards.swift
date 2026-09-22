import SwiftUI

/// A white card surface (§8.2).
///
/// Cards use a border or a shadow, not both stacked into noise.
struct CardContainer<Content: View>: View {
    /// Corner radius, within the 16–20pt range §8.2 specifies.
    var cornerRadius: CGFloat = 18
    /// The card's contents.
    @ViewBuilder var content: Content

    /// The view body.
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Palette.borderSubtle, lineWidth: 1)
            }
            .shadow(color: Palette.cardShadow, radius: 3, x: 0, y: 1)
    }
}

/// A gradient hero card with white text (§8.2).
///
/// The gradient runs at 135°, purple to gradient-end, which `topLeading` to
/// `bottomTrailing` expresses.
struct HeroCard<Content: View>: View {
    /// Corner radius, within the 16–20pt range §8.2 specifies.
    var cornerRadius: CGFloat = 20
    /// The card's contents.
    @ViewBuilder var content: Content

    /// The view body.
    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(
                    colors: [Palette.heroGradientStart, Palette.heroGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
