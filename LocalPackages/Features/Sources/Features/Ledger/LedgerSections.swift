import SwiftUI
import Domain

/// Period, account and category filter rows (§7.4).
///
/// Its own view so that typing or scrolling elsewhere on the screen does not rebuild
/// three chip rows.
struct LedgerFiltersBar: View {
    /// Accounts to offer, closed ones included so history stays browsable (§4.7).
    let accounts: [Domain.Account]
    /// Categories to offer.
    let categories: [Domain.Category]
    /// The selected period.
    @Binding var period: LedgerPeriod
    /// The selected account, or `nil` for all.
    @Binding var accountID: UUID?
    /// The selected category, or `nil` for all.
    @Binding var categoryID: UUID?

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedPillControl(
                options: LedgerPeriod.allCases,
                selection: $period,
                display: \.filterLabel
            )
            FilterChipRow(title: "Accounts") {
                FilterChip(label: "All accounts", isSelected: accountID == nil) {
                    accountID = nil
                }
                ForEach(accounts) { account in
                    FilterChip(
                        label: account.isClosed ? "\(account.name) (closed)" : account.name,
                        isSelected: accountID == account.id
                    ) {
                        accountID = account.id
                    }
                }
            }
            // Hidden entirely when nothing has been categorised yet: a lone
            // "All categories" chip filters nothing.
            if !categories.isEmpty {
                FilterChipRow(title: "Categories") {
                    FilterChip(label: "All categories", isSelected: categoryID == nil) {
                        categoryID = nil
                    }
                    ForEach(categories) { category in
                        FilterChip(label: category.label, isSelected: categoryID == category.id) {
                            categoryID = category.id
                        }
                    }
                }
            }
        }
    }
}

/// Spend, count, income and net for the filtered period (§7.4).
///
/// Transfers and adjustments appear in the list but never in these totals.
struct LedgerSummaryBanner: View {
    /// The period and account scope.
    let scopeLabel: String
    /// Total spent in the period.
    let spendCents: Int
    /// Total income in the period.
    let incomeCents: Int
    /// Income minus spend.
    let netCents: Int
    /// How many transactions the banner reports.
    let count: Int
    /// The display currency.
    let currencyCode: String

    /// The view body.
    var body: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(scopeLabel)
                    .font(Typography.rowSecondary)
                    .opacity(0.9)
                Text(money(spendCents)).moneyText()
                Text("\(count) transactions · Income \(money(incomeCents)) "
                   + "· Net \(signedMoney(netCents))")
                    .font(Typography.rowSecondary)
                    .opacity(0.9)
            }
        }
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }

    /// Formats a net figure with an explicit sign.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string, signed.
    private func signedMoney(_ cents: Int) -> String {
        let magnitude = money(abs(cents))
        if cents == 0 { return magnitude }
        return (cents > 0 ? "+" : "−") + magnitude
    }
}

/// Unposted rows above today's transactions, visually lighter (§7.4).
struct LedgerUpcomingSection: View {
    /// The unposted rows, soonest first.
    let rows: [LedgerRowModel]
    /// Opens a row's detail screen.
    let onSelect: (Domain.Transaction) -> Void

    /// The view body.
    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Upcoming").sectionLabel()
                CardContainer {
                    VStack(spacing: 12) {
                        ForEach(rows) { row in
                            if row.id != rows.first?.id {
                                Divider().overlay(Palette.borderSubtle)
                            }
                            LedgerRowButton(row: row, isUpcoming: true, onSelect: onSelect)
                        }
                    }
                }
            }
        }
    }
}

/// Posted history, grouped by day (§7.4).
struct LedgerPostedSection: View {
    /// The posted days, newest first.
    let days: [LedgerDay]
    /// Whether the filters matched nothing (§7.0).
    let isFilteredToZero: Bool
    /// Opens a row's detail screen.
    let onSelect: (Domain.Transaction) -> Void

    /// The view body.
    var body: some View {
        if isFilteredToZero {
            CardContainer {
                FilteredEmptyNotice(message: "No transactions match these filters yet.")
            }
        } else {
            ForEach(days) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        group.day,
                        format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                    )
                    .sectionLabel()
                    CardContainer {
                        VStack(spacing: 12) {
                            ForEach(group.rows) { row in
                                if row.id != group.rows.first?.id {
                                    Divider().overlay(Palette.borderSubtle)
                                }
                                LedgerRowButton(row: row, onSelect: onSelect)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One row, tappable into its read-only detail (§7.4).
///
/// Every row opens, including one touching a closed account: reading history is always
/// allowed, and it is the detail screen that withholds the Edit button when the account
/// is closed (§4.7). Tapping a row used to open the edit form directly.
struct LedgerRowButton: View {
    /// The row to render.
    let row: LedgerRowModel
    /// Whether it belongs to the Upcoming section.
    var isUpcoming = false
    /// Opens the row's detail screen.
    let onSelect: (Domain.Transaction) -> Void

    /// The view body.
    var body: some View {
        Button {
            onSelect(row.editableTransaction)
        } label: {
            LedgerRowView(row: row, isUpcoming: isUpcoming)
        }
        .buttonStyle(.plain)
    }
}
