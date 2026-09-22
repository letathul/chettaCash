import SwiftUI
import Domain

/// The three-step onboarding flow (§7.10).
///
/// Shown once, gated by `AppSettings.hasCompletedOnboarding`. Progress dots at the
/// top; full-screen steps below.
public struct OnboardingView: View {
    /// The flow's view model.
    @State private var model: OnboardingViewModel
    /// Called when onboarding finishes, by any path.
    private let onFinish: () -> Void

    /// Creates the flow.
    /// - Parameters:
    ///   - model: The flow's view model.
    ///   - onFinish: Called when onboarding finishes, by any path.
    public init(model: OnboardingViewModel, onFinish: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    /// The view body.
    public var body: some View {
        VStack(spacing: 0) {
            progressDots
            content
        }
        .background(Palette.appBackground)
        .task { await model.load() }
    }

    /// One dot per step, filled up to the current one.
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases) { step in
                Capsule()
                    .fill(
                        step.rawValue <= model.step.rawValue
                            ? Palette.brandPurple
                            : Palette.toggleOff
                    )
                    .frame(width: step == model.step ? 22 : 8, height: 8)
            }
        }
        .padding(.top, 16)
        .animation(.snappy(duration: 0.25), value: model.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    /// The current step.
    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            OnboardingWelcomeStep { model.advance() }
        case .accounts:
            OnboardingAccountsStep(model: model, onContinue: { model.advance() }, onSkip: skip)
        case .notifications:
            OnboardingNotificationsStep(model: model, onFinish: finish)
        }
    }

    /// Finishes without adding accounts, landing on the Dashboard's empty state (§7.10).
    private func skip() {
        model.advance()
    }

    /// Marks onboarding done and hands control back to the app.
    ///
    /// A user who skipped, or added nothing, must still land somewhere they can record
    /// a transaction, so a Cash account is created first and announced on the Dashboard
    /// (§7.10). It no-ops when the user added an account of their own.
    private func finish() {
        Task {
            await model.ensureStarterAccount()
            model.finish()
            onFinish()
        }
    }
}

/// Step 1: a static value-prop screen with a single CTA (§7.10).
///
/// There is deliberately **no skip link** — there is nothing to skip past.
struct OnboardingWelcomeStep: View {
    /// Moves to the next step.
    let onStart: () -> Void

    /// The view body.
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.brandPurple)
                    .accessibilityHidden(true)
                Text("Chetta Cash")
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("Your accounts, spending, trials and warranties in one place.")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    valueRow("banknote", "See what you can actually spend")
                    valueRow("book.closed", "Log expenses, income and transfers")
                    valueRow("shield.checkered", "Never miss a trial ending or a bill due")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            Spacer()
            Button(action: onStart) {
                Text("Get started")
                    .font(Typography.rowPrimary.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.brandPurple, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// One value-proposition row.
    /// - Parameters:
    ///   - icon: The SF Symbol to draw.
    ///   - text: What it promises.
    /// - Returns: The row view.
    private func valueRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(Palette.brandPurple)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
