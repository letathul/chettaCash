import SwiftUI

/// The app's search field (§7.3, §7.8).
///
/// Its own view, and bound to a draft string rather than to a view model, so that a
/// keystroke invalidates this and nothing else on the screen. Callers debounce the
/// draft into their filter with `.task(id:)`.
///
/// Shared by the search screen and the purchase picker, which previously carried a
/// hand-rolled copy each.
struct SearchField: View {
    /// The placeholder shown when empty.
    let placeholder: String
    /// The text being typed.
    @Binding var text: String
    /// Keyboard focus, owned by the screen so its Done button can release it.
    @FocusState.Binding var isFocused: Bool

    /// The view body.
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(Typography.rowPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.placeholder)
                        .iconTapTarget(expandedBy: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.surface, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.borderSubtle, lineWidth: 1)
        }
    }
}
