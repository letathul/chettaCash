import SwiftUI

/// A toggle row whose helper caption changes with its state (§8.4).
struct ToggleRow: View {
    /// The row's label.
    let title: String
    /// Whether the toggle is on.
    @Binding var isOn: Bool
    /// Builds the caption for the current state.
    let helperText: (Bool) -> String

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.brandPurple)
            Text(helperText(isOn))
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
                .animation(.none, value: isOn)
        }
    }
}

/// A segmented pill control (§8.4).
///
/// The selected segment is a raised pill on a tinted track. At accessibility text
/// sizes the segments stack vertically rather than truncating, which is the §12
/// "layout genuinely cannot adapt" case handled rather than capped.
struct SegmentedPillControl<Value: Hashable>: View {
    /// The segments, in order.
    let options: [Value]
    /// The current selection.
    @Binding var selection: Value
    /// Renders a value as its display text.
    let display: (Value) -> String

    /// The viewer's current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The view body.
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))

        layout {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(4)
        .background(Palette.segmentTrack, in: .rect(cornerRadius: 12))
    }

    /// Builds one segment.
    /// - Parameter option: The value the segment selects.
    /// - Returns: The segment view.
    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(display(option))
                .font(Typography.rowSecondary.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Palette.segmentSelected)
                            .shadow(color: Palette.cardShadow, radius: 2, x: 0, y: 1)
                    }
                }
                // Unselected segments draw no background, so without this only their
                // glyphs would be live — and those are the ones you need to hit.
                .tappableSurface()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
