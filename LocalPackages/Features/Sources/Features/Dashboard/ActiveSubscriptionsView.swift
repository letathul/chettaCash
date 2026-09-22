import SwiftUI
import Domain

/// Every active recurring rule (§7.2).
///
/// This is a view over active rules, not a second registry: it covers standalone
/// recurring transactions and Vault-linked subscriptions alike, because both are
/// rules.
struct ActiveSubscriptionsView: View {
    /// The screen's view model.
    let model: DashboardViewModel

    /// The view body.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.activeSubscriptions.isEmpty {
                    CardContainer {
                        EmptyStateView(
                            icon: "arrow.trianglehead.2.clockwise",
                            title: "No active subscriptions",
                            message: "Turn on Recurring when logging a transaction to start one."
                        )
                    }
                } else {
                    ForEach(model.activeSubscriptions) { rule in
                        CardContainer { subscriptionRow(rule) }
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.appBackground)
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One subscription row: name, amount, frequency, account and next charge.
    /// - Parameter rule: The rule to show.
    /// - Returns: The row view.
    private func subscriptionRow(_ rule: Domain.RecurringRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.name.isEmpty ? "Recurring charge" : rule.name)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(money(rule.amountCents) + "/" + rule.frequency.shortSuffix)
                    .moneyText(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text(subtitle(for: rule))
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// The account and next charge date.
    /// - Parameter rule: The rule to describe.
    /// - Returns: The subtitle.
    private func subtitle(for rule: Domain.RecurringRule) -> String {
        let account = model.account(id: rule.accountID)?.name ?? "No account"
        guard let next = model.nextChargeDate(for: rule) else { return account }
        return account + " · next " + next.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}
