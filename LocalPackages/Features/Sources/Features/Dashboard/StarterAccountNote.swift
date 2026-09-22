import SwiftUI

/// Explains the account the app created on the user's behalf (§7.10).
///
/// Creating an account silently would leave the user wondering where "Cash" came from,
/// so the fallback always says so and stays until dismissed.
struct StarterAccountNote: View {
    /// Clears the note for good.
    let onDismiss: () -> Void

    /// The view body.
    var body: some View {
        CardContainer {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.brandPurple)
                    .accessibilityHidden(true)
                Text("We added a Cash account so you can start logging right away. "
                   + "Rename it anytime.")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .iconTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }
}
