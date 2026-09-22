import SwiftUI

/// Wraps a form field with the shared validation treatment (§7.11).
///
/// All six forms validate identically. Validation is triggered on a Save attempt
/// only — never on blur, never live as the user types — so the caller passes `error`
/// as `nil` until Save is pressed. The error then clears the instant the field
/// becomes valid, which happens naturally as the caller re-evaluates.
///
/// The caption's height is reserved whether or not an error is showing, so the form
/// does not jump when one appears.
struct ValidatedField<Content: View>: View {
    /// The field's label.
    let label: String
    /// The message to show, or `nil` when the field is valid.
    let error: String?
    /// The field itself.
    @ViewBuilder var content: Content

    /// Whether the field is currently invalid.
    private var isInvalid: Bool { error != nil }

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .sectionLabel(color: isInvalid ? Palette.negativeRed : Palette.textSecondary)

            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.surface, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isInvalid ? Palette.negativeRed : Palette.borderSubtle,
                            lineWidth: isInvalid ? 1.5 : 1
                        )
                }

            Text(error ?? " ")
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.negativeRed)
                .opacity(isInvalid ? 1 : 0)
                .accessibilityHidden(!isInvalid)
        }
        .animation(.snappy(duration: 0.15), value: isInvalid)
    }
}
