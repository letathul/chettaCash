import SwiftUI

/// A labelled, horizontally scrolling row of filter chips (§7.3, §7.4).
///
/// Shared by the Ledger and the search screen, which previously carried a private
/// copy each of this and ``FilterChip``.
struct FilterChipRow<Content: View>: View {
    /// The row's section label.
    let title: String
    /// The chips.
    @ViewBuilder let content: Content

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).sectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content }
                    .padding(.horizontal, 1)
            }
        }
    }
}

/// One filter chip.
struct FilterChip: View {
    /// The chip's text.
    let label: String
    /// Whether it is the active filter.
    let isSelected: Bool
    /// Selects this filter.
    let action: () -> Void

    /// The view body.
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.rowSecondary)
                .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Palette.brandPurple : Palette.surface, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Palette.borderSubtle, lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
