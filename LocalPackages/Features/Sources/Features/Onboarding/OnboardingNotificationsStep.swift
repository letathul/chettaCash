import SwiftUI
import Domain

/// Step 3: request notification permission (§7.10).
///
/// "Enable notifications" triggers the **real** system prompt, not a mock toggle.
/// "Maybe later" skips, ending in the same state as never granting permission.
struct OnboardingNotificationsStep: View {
    /// The flow's view model.
    let model: OnboardingViewModel
    /// Finishes onboarding.
    let onFinish: () -> Void

    /// Whether the prompt has been answered during this step.
    @State private var hasAsked = false

    /// The view body.
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Palette.attentionAmber)
                    .accessibilityHidden(true)
                Text("Stay ahead of dates")
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Chetta Cash can remind you before a card payment is due, "
                   + "before a free trial starts charging, and before a warranty runs out.")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if model.notificationsAuthorized {
                    Label("Notifications are on", systemImage: "checkmark.circle.fill")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.positiveGreen)
                } else if hasAsked {
                    Text("You can turn these on later in iOS Settings ▸ Notifications.")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
            actions
        }
        .background(Palette.appBackground)
    }

    /// The filled capsule shared by both primary actions.
    ///
    /// The styling belongs to the label rather than the Button: chained onto the Button
    /// it would paint a capsule behind a control only as wide as its text (§8.4).
    /// - Parameter title: The button text.
    /// - Returns: The styled label.
    private func capsuleLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.rowPrimary.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.brandPurple, in: .capsule)
    }

    /// The request button and the skip link.
    private var actions: some View {
        VStack(spacing: 10) {
            if model.notificationsAuthorized || hasAsked {
                Button(action: onFinish) {
                    capsuleLabel("Done")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task {
                        await model.requestNotifications()
                        hasAsked = true
                    }
                } label: {
                    capsuleLabel("Enable notifications")
                }
                .buttonStyle(.plain)

                Button(action: onFinish) {
                    Text("Maybe later")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .iconTapTarget()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}
