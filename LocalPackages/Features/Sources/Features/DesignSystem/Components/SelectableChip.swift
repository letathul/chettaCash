import SwiftUI

/// A capsule chip that reads as selected or not (§8.4).
///
/// Shared by the account form's group row and the group page's name presets, so the
/// two cannot drift apart visually.
struct SelectableChip: View {
    /// The chip's label.
    let title: String
    /// Whether the chip is currently chosen.
    let isSelected: Bool
    /// What tapping the chip does.
    let action: () -> Void

    /// The view body.
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.rowSecondary)
                .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Palette.brandPurple : Palette.segmentTrack, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
