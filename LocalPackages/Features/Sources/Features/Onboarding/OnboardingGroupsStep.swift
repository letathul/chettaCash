import SwiftUI
import Domain

/// The list phase of onboarding step 2: groups, their accounts, and the way on (§7.10).
///
/// Deliberately does not reuse ``GroupBlock``, which is bound to ``SettingsViewModel``
/// for collapse state, subtotals and reorder arrows — none of which exist during
/// onboarding.
struct OnboardingGroupsStep: View {
    /// The flow's view model.
    let model: OnboardingViewModel
    /// Opens the add-account sheet for a group.
    let onAddAccount: (Domain.AccountGroup) -> Void
    /// Returns to the group page.
    let onNewGroup: () -> Void
    /// Moves to the next step.
    let onContinue: () -> Void
    /// Bypasses account creation entirely (§7.10).
    let onSkip: () -> Void

    /// The view body.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let errorMessage = model.errorMessage {
                        ErrorBanner(message: errorMessage) {}
                    }
                    ForEach(model.groups) { group in
                        groupCard(group)
                    }
                    newGroupTrigger
                }
                .padding(16)
            }
            footer
        }
        .background(Palette.appBackground)
    }

    /// The step's title and explanation.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add your accounts")
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("Add as many as you like — you can always add more later.")
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// One group and the accounts added to it during this pass.
    /// - Parameter group: The group to show.
    /// - Returns: The card view.
    private func groupCard(_ group: Domain.AccountGroup) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text(group.name)
                    .font(Typography.rowPrimary.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                ForEach(model.addedAccounts(in: group)) { account in
                    accountRow(account)
                }
                Button { onAddAccount(group) } label: {
                    Text("+ Add account or card")
                        .font(Typography.rowSecondary.weight(.semibold))
                        .foregroundStyle(Palette.brandPurple)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tappableSurface()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add an account or card to \(group.name)")
            }
        }
    }

    /// One added account, with the checkmark that confirms it saved.
    /// - Parameter account: The account to show.
    /// - Returns: The row view.
    private func accountRow(_ account: Domain.Account) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Palette.positiveGreen)
                .accessibilityHidden(true)
            Text(account.name)
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 8)
            Text(CurrencyFormatter.string(
                fromCents: account.cachedBalanceCents,
                currencyCode: model.settings.currencyCode
            ))
            .moneyText(Typography.rowSecondary)
            .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Added \(account.name)")
    }

    /// The dashed trigger back to the group page.
    private var newGroupTrigger: some View {
        Button(action: onNewGroup) {
            Text("+ New group")
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.brandPurple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            Palette.dashedAccent,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
                .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// Continue and the skip link.
    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                guard model.hasAnyAccount else { return }
                onContinue()
            } label: {
                Text(model.continueTitle)
                    .font(Typography.rowPrimary.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        model.hasAnyAccount ? Palette.brandPurple : Palette.placeholder,
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.hasAnyAccount)

            Button(action: onSkip) {
                Text("Skip for now")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .iconTapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}
