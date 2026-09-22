import SwiftUI
import Domain

/// The Today sheet, grouped by time horizon (§7.2).
///
/// Each section is **omitted entirely when empty** rather than showing an empty
/// state. This overlaps deliberately with the Ledger's Upcoming section but is
/// scoped differently: this is a near-term glance, the Ledger is the full
/// chronological list in context.
struct TodaySheet: View {
    /// The screen's view model.
    let model: DashboardViewModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// Whether the active subscriptions list is showing.
    @State private var isShowingSubscriptions = false

    /// What needs attention today.
    var digest: TodayDigest { model.digest }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if digest.isQuietDay { quietState }
                    if !digest.missedPayments.isEmpty { missedPaymentsSection }
                    if !digest.unassignedEntries.isEmpty { unassignedSection }
                    if digest.postedTodayCount > 0 { todaySection }
                    if !digest.dueSoon.isEmpty { dueSoonSection }
                    if !digest.upcomingCharges.isEmpty { upcomingSection }
                    if !digest.endingSoon.isEmpty { endingSoonSection }
                    subscriptionsLink
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isShowingSubscriptions) {
                ActiveSubscriptionsView(model: model)
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Shown when nothing at all needs attention.
    private var quietState: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing due")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text("No spending today, nothing due and nothing charging soon.")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// Statements whose due date passed while still unpaid (§4.6).
    ///
    /// Sits above everything else, and on its own surface rather than a plain card:
    /// under cumulative statements the amount is never *lost*, it rolls into the next
    /// statement — which is exactly why it needs saying, since the next statement
    /// carries a later due date and nothing else on this sheet would mention it.
    private var missedPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Missed payments").sectionLabel()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.rowSecondary)
                    Text("These statements passed their due date unpaid. The amount has "
                        + "rolled into the card's current balance.")
                        .font(Typography.rowSecondary)
                }
                .foregroundStyle(Palette.errorBannerText)

                ForEach(digest.missedPayments) { item in
                    Divider().overlay(Palette.errorBannerBorder)
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.accountName)
                                .font(Typography.rowPrimary)
                                .foregroundStyle(Palette.textPrimary)
                            Text("\(money(item.outstandingCents)) due "
                                + item.statement.dueDate.formatted(
                                    .dateTime.day().month(.abbreviated)
                                ))
                                .font(Typography.rowSecondary)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        daysPill(item.daysOverdue, isOverdue: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.errorBannerBackground, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Palette.errorBannerBorder, lineWidth: 1)
            }
        }
    }

    /// What happened today.
    private var todaySection: some View {
        section("Today") {
            row(
                title: money(digest.spentTodayCents) + " spent",
                subtitle: "\(digest.postedTodayCount) "
                    + (digest.postedTodayCount == 1 ? "transaction" : "transactions") + " posted",
                trailing: nil
            )
        }
    }

    /// Card statements inside their reminder window (§4.6).
    private var dueSoonSection: some View {
        section("Due soon") {
            ForEach(digest.dueSoon) { item in
                if item.id != digest.dueSoon.first?.id {
                    Divider().overlay(Palette.borderSubtle)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.accountName)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text(partialPaymentLine(item))
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    daysPill(item.daysRemaining, isOverdue: item.isOverdue)
                }
            }
        }
    }

    /// The next occurrence of each active rule.
    private var upcomingSection: some View {
        section("Upcoming charges") {
            ForEach(digest.upcomingCharges) { item in
                if item.id != digest.upcomingCharges.first?.id {
                    Divider().overlay(Palette.borderSubtle)
                }
                row(
                    title: item.rule.name.isEmpty ? "Recurring charge" : item.rule.name,
                    subtitle: item.accountName.isEmpty
                        ? item.date.formatted(.dateTime.day().month(.abbreviated))
                        : "\(item.accountName) · "
                            + item.date.formatted(.dateTime.day().month(.abbreviated)),
                    trailing: money(item.rule.amountCents)
                )
            }
        }
    }

    /// Trials and warranties approaching expiry.
    private var endingSoonSection: some View {
        section("Ending soon") {
            ForEach(digest.endingSoon) { item in
                if item.id != digest.endingSoon.first?.id {
                    Divider().overlay(Palette.borderSubtle)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.item.name)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text(item.kind == .trial ? "Free trial ends" : "Warranty expires")
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    daysPill(item.daysRemaining, isOverdue: item.daysRemaining < 0)
                }
            }
        }
    }

    /// The link into the single subscriptions registry.
    private var subscriptionsLink: some View {
        Button { isShowingSubscriptions = true } label: {
            Text("View all active subscriptions")
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.brandPurple)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// A titled card section.
    /// - Parameters:
    ///   - title: The section label.
    ///   - content: The section's rows.
    /// - Returns: The section view.
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 12) { content() }
            }
        }
    }

    /// A simple two-line row with an optional trailing figure.
    /// - Parameters:
    ///   - title: The primary line.
    ///   - subtitle: The secondary line.
    ///   - trailing: An optional trailing amount.
    /// - Returns: The row view.
    private func row(title: String, subtitle: String, trailing: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .moneyText(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    /// The days-remaining pill.
    /// - Parameters:
    ///   - days: Whole days remaining, negative when past.
    ///   - isOverdue: Whether the date has passed.
    /// - Returns: The pill view.
    private func daysPill(_ days: Int, isOverdue: Bool) -> some View {
        let tint = isOverdue ? Palette.negativeRed : Palette.attentionAmber
        let label: String
        if isOverdue {
            label = "\(abs(days))d overdue"
        } else if days == 0 {
            label = "Today"
        } else {
            label = "\(days)d"
        }
        return Text(label)
            .font(Typography.errorCaption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: .capsule)
            .fixedSize()
    }

    /// The partial-payment line required by §4.6.
    /// - Parameter item: The statement due.
    /// - Returns: The formatted line.
    private func partialPaymentLine(_ item: DueStatementItem) -> String {
        let due = item.statement.dueDate.formatted(.dateTime.day().month(.abbreviated))
        guard item.paidCents > 0 else {
            return "\(money(item.outstandingCents)) due \(due)"
        }
        return "\(money(item.statement.effectiveBalanceCents)) · "
             + "\(money(item.paidCents)) paid · \(money(item.outstandingCents)) due \(due)"
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}
