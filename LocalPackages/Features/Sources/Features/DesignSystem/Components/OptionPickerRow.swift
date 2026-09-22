import SwiftUI

/// A label-and-value row that opens an ``OptionPickerSheet`` on tap (§8.4).
///
/// The row owns its own presentation state, so a call site stays a single declaration —
/// no `@State` flag and no `.sheet` modifier to thread through the enclosing view.
struct OptionPickerRow<Value: Hashable>: View {
    /// The row's leading label, reused as the sheet's title.
    let label: String
    /// The values to offer, in order.
    let options: [Value]
    /// The current selection.
    @Binding var selection: Value
    /// Renders a value as its display text.
    let display: (Value) -> String
    /// Renders a value's explanatory line in the sheet, or `nil` for a bare row.
    var subtitle: (Value) -> String? = { _ in nil }

    /// Whether the picker sheet is showing.
    @State private var isPresented = false

    /// The view body.
    var body: some View {
        Button { isPresented = true } label: {
            // Side by side until the label and value stop fitting, then stacked —
            // squeezing the value into a two-line column reads worse (§12).
            ViewThatFits(in: .horizontal) {
                HStack {
                    labelText
                    Spacer(minLength: 12)
                    valueText
                }
                VStack(alignment: .leading, spacing: 4) {
                    labelText
                    valueText
                }
            }
            // On the ViewThatFits result, so the gap between label and value is live in
            // whichever of the two layouts wins.
            .tappableSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(display(selection))
        .accessibilityHint("Double tap to choose")
        .sheet(isPresented: $isPresented) {
            OptionPickerSheet(
                title: label,
                options: options,
                selection: $selection,
                display: display,
                subtitle: subtitle
            )
        }
    }

    /// The row's leading label.
    private var labelText: some View {
        Text(label)
            .font(Typography.rowPrimary)
            .foregroundStyle(Palette.textPrimary)
    }

    /// The current value and its picker affordance.
    private var valueText: some View {
        HStack(spacing: 4) {
            Text(display(selection))
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.brandPurple)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
