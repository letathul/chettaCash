import Foundation
import Domain

/// Rebuilding the Dashboard's derived figures (§7.1, §7.2).
///
/// Split from ``DashboardViewModel`` to keep each file within the 300-line limit.
extension DashboardViewModel {

    /// Recomputes every derived figure in one pass.
    ///
    /// Call after the data changes and after the display currency changes — the recent
    /// rows carry formatted amounts and resolved names.
    public func refresh() {
        accountsByID = Dictionary(
            accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        categoriesByID = Dictionary(
            categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        openAccounts = accounts.filter { !$0.isClosed }
        // An id that no longer resolves to an open account behaves exactly like no
        // focus at all, rather than erroring or silently clearing the setting.
        focusedAccount = settings.focusedAccountID
            .flatMap { accountsByID[$0] }
            .flatMap { $0.isClosed ? nil : $0 }
        displayedAccounts = focusedAccount.map { [$0] } ?? openAccounts
        // The transactions the focused account's figures, trends and lists are all
        // built from. Unscoped when nothing is focused.
        let scopedTransactions = focusedAccount.map { account in
            transactions.filter { $0.accountID == account.id }
        } ?? transactions

        availableCashCents = BalanceEngine.availableCashCents(
            accounts: displayedAccounts, transactions: transactions
        )
        netWorthCents = BalanceEngine.netWorthCents(
            accounts: displayedAccounts, transactions: transactions
        )
        activeSubscriptions = rules.filter(\.isActive).sorted { $0.name < $1.name }

        // One pass over the transactions for the next charge of every rule, rather than
        // one pass per rule from inside the subscriptions list's body.
        let now = Date.now
        var nextCharge: [UUID: Date] = [:]
        for transaction in transactions {
            guard let ruleID = transaction.recurringRuleID, transaction.date > now else {
                continue
            }
            if let existing = nextCharge[ruleID], existing <= transaction.date { continue }
            nextCharge[ruleID] = transaction.date
        }
        nextChargeByRuleID = nextCharge

        let currencyCode = settings.currencyCode
        updateRecentSection(scopedTransactions: scopedTransactions, currencyCode: currencyCode, now: now)
        heroPages = buildHeroPages(now: now)
    }

    /// Fills the Today/Recent section: today's posted transactions when there are any,
    /// otherwise the most recent ones.
    /// - Parameters:
    ///   - scopedTransactions: The transactions in play, already scoped to the focused
    ///     account when one is set.
    ///   - currencyCode: The display currency.
    ///   - now: The moment "today" is evaluated against.
    private func updateRecentSection(
        scopedTransactions: [Domain.Transaction],
        currencyCode: String,
        now: Date
    ) {
        let today = TodayBuilder.dayRange(containing: now)
        let postedToday = scopedTransactions
            .filter { today.contains($0.date) && BalanceEngine.isPosted($0, asOf: now) }
            .sorted { $0.date > $1.date }

        if postedToday.isEmpty {
            recentSectionTitle = "Recent"
            isShowingRecentFallback = true
            recentTransactions = scopedTransactions
                .filter { BalanceEngine.isPosted($0) }
                .sorted { $0.date > $1.date }
                .prefix(Self.recentRowLimit)
                .map { $0 }
            recentRows = recentTransactions.map { recentRow(for: $0, currencyCode: currencyCode) }
        } else {
            recentSectionTitle = "Today"
            isShowingRecentFallback = false
            recentTransactions = []
            recentRows = postedToday.map { recentRow(for: $0, currencyCode: currencyCode) }
        }
    }

    /// Renders one Recent row.
    /// - Parameters:
    ///   - transaction: The transaction to show.
    ///   - currencyCode: The display currency.
    /// - Returns: The row model.
    private func recentRow(
        for transaction: Domain.Transaction,
        currencyCode: String
    ) -> RecentRowModel {
        let resolved = category(id: transaction.categoryID)
        let isTransfer = transaction.transferGroupID != nil
        let cents = BalanceEngine.signedAmountCents(for: transaction)
        let magnitude = CurrencyFormatter.string(
            fromCents: abs(cents), currencyCode: currencyCode
        )
        return RecentRowModel(
            id: transaction.id,
            title: transaction.merchant.isEmpty
                ? fallbackTitle(for: transaction)
                : transaction.merchant,
            subtitle: Self.relativeDay(transaction.date),
            amountText: cents == 0 ? magnitude : (cents < 0 ? "−" : "+") + magnitude,
            tone: transaction.type == .income ? .positive : .primary,
            avatar: avatar(for: transaction, category: resolved),
            glyph: CategoryGlyph.name(
                categoryLabel: resolved?.label, type: transaction.type, isTransfer: isTransfer
            ),
            transaction: transaction
        )
    }

    /// The avatar tint a row reads in.
    /// - Parameters:
    ///   - transaction: The transaction to describe.
    ///   - category: Its resolved category, if any.
    /// - Returns: The avatar role.
    private func avatar(
        for transaction: Domain.Transaction,
        category: Domain.Category?
    ) -> RowAvatar {
        if transaction.transferGroupID != nil { return .neutral }
        if transaction.type == .income { return .income }
        guard let category else { return .neutral }
        return .category(label: category.label, sortIndex: category.sortIndex)
    }

    /// Renders a date the way the mock's rows read it — "Today", "Yesterday", "Mon".
    ///
    /// Built here rather than in a row's `body`: a SwiftUI body must do no date or
    /// string formatting of its own (§8.4). `nonisolated` because it is pure — it
    /// reads nothing off the view model.
    ///
    /// - Parameter date: The transaction's date.
    /// - Returns: The subtitle text.
    nonisolated static func relativeDay(
        _ date: Date, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return date.formatted(.dateTime.weekday(.abbreviated))
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// The title used when no merchant was entered.
    /// - Parameter transaction: The transaction to describe.
    /// - Returns: The stand-in title.
    private func fallbackTitle(for transaction: Domain.Transaction) -> String {
        switch transaction.type {
        case .adjustment: return "Balance adjustment"
        case .transferIn, .transferOut: return "Transfer"
        default: return "No merchant"
        }
    }
}

/// One row in the Dashboard's Recent list, with every string already rendered (§7.1).
struct RecentRowModel: Identifiable, Hashable {
    /// The row's identity, which is the transaction's.
    let id: UUID
    /// The merchant, or a stand-in when the transaction has none.
    let title: String
    /// When it happened, read as "Today", "Yesterday", "Mon" or a date.
    let subtitle: String
    /// The signed, currency-formatted amount.
    let amountText: String
    /// Which palette entry the amount reads in.
    let tone: AmountTone
    /// Which tint the row's circular avatar takes.
    let avatar: RowAvatar
    /// The SF Symbol drawn inside that avatar.
    let glyph: String
    /// The transaction a tap opens, which is its read-only detail (§7.4).
    let transaction: Domain.Transaction
}
