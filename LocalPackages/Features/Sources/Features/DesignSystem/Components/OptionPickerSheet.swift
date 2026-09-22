import SwiftUI

/// A detented sheet that lists every option at once and dismisses on choice (§8.4).
///
/// Replaces the former tap-to-cycle row, which hid the choices, applied every value it
/// passed through on the way, and left no room to explain what a choice meant. Each row
/// may carry a `subtitle` for exactly that.
struct OptionPickerSheet<Value: Hashable>: View {
    /// The sheet's navigation title, taken from the field's label.
    let title: String
    /// The values to offer, in order.
    let options: [Value]
    /// The current selection.
    @Binding var selection: Value
    /// Renders a value as its row title.
    let display: (Value) -> String
    /// Renders a value's explanatory line, or `nil` for a bare row.
    var subtitle: (Value) -> String? = { _ in nil }

    /// Dismisses the sheet once a value is chosen.
    @Environment(\.dismiss) private var dismiss
    /// The viewer's current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                CardContainer {
                    VStack(spacing: 0) {
                        // Identified by the value, not the index: `Value` is already
                        // `Hashable`, and index identity makes a row's state follow the
                        // position rather than the option it draws.
                        ForEach(options, id: \.self) { option in
                            if option != options.first { Divider().overlay(Palette.borderSubtle) }
                            row(option)
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }

    /// Builds one option row.
    /// - Parameter option: The value the row selects.
    /// - Returns: The row view.
    private func row(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display(option))
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    if let detail = subtitle(option) {
                        Text(detail)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                // Always laid out, so choosing a value never shifts the rows sideways.
                Image(systemName: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.brandPurple)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The detents the sheet offers.
    ///
    /// At accessibility text sizes the estimate below stops being meaningful, so the
    /// sheet opens full height rather than at a guess that would clip the first row.
    private var detents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(estimatedHeight), .large]
    }

    /// A height that fits the whole list for the common case of a handful of options.
    ///
    /// Deliberately an estimate: `.large` is always offered alongside it, and the list
    /// scrolls, so overshooting or undershooting degrades to a drag rather than a bug.
    private var estimatedHeight: CGFloat {
        let hasSubtitles = options.contains { subtitle($0) != nil }
        let rowHeight: CGFloat = hasSubtitles ? 66 : 46
        let chrome: CGFloat = 108
        return min(chrome + CGFloat(options.count) * rowHeight, 560)
    }
}
