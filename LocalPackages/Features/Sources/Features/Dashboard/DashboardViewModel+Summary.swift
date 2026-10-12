import Foundation
import Domain

/// Rebuilding the Dashboard's expense summary rows (§7.1).
///
/// Split from ``DashboardViewModel`` to keep each file within the 300-line limit.
extension DashboardViewModel {

    /// How many categories get their own slice before the rest fold into "Other".
    static let categorySliceLimit = 4
    /// The window, in days, that "Due in 7 days" looks across.
    static let dueWindowDays = 7

    /// Recomputes the expense summary and the rows built from it.
    ///
    /// Reads only expenses, so nothing here depends on income having been logged.
    func refreshSummary() {
        let now = Date.now
        spendSummary = SpendSummaryEngine.summary(
            transactions: transactions, products: products, rules: rules, reference: now
        )
        dueWithinWeekCents = SpendSummaryEngine.dueWithinCents(
            digest: digest, days: Self.dueWindowDays, reference: now
        )
        categorySlices = makeCategorySlices(from: spendSummary.byCategory)
        accountSpendRows = makeAccountRows(from: spendSummary.byAccount)
    }

    /// Folds the category breakdown into a few named slices plus "Other".
    /// - Parameter spend: The month's spending by category, largest first.
    /// - Returns: The slices, largest first, with "Other" last.
    private func makeCategorySlices(from spend: [CategorySpend]) -> [CategorySliceModel] {
        var slices = spend.prefix(Self.categorySliceLimit).map { entry -> CategorySliceModel in
            let match = category(id: entry.categoryID)
            return CategorySliceModel(
                id: entry.categoryID?.uuidString ?? "uncategorised",
                label: match?.label ?? "Uncategorised",
                sortIndex: match?.sortIndex ?? 0,
                cents: entry.cents,
                isOther: false
            )
        }
        let rest = spend.dropFirst(Self.categorySliceLimit).reduce(0) { $0 + $1.cents }
        if rest > 0 {
            slices.append(CategorySliceModel(
                id: "other", label: "Other", sortIndex: 0, cents: rest, isOther: true
            ))
        }
        return slices
    }

    /// Builds the "Spent by account" rows.
    ///
    /// An account earns a row when it took spending this month or, for a card, still
    /// owes something — a card paid off last month and unused since is not news.
    ///
    /// - Parameter spend: The month's spending by account, largest first.
    /// - Returns: The rows, largest spend first.
    private func makeAccountRows(from spend: [AccountSpend]) -> [AccountSpendRowModel] {
        let spendByID = Dictionary(
            spend.compactMap { entry in entry.accountID.map { ($0, entry.cents) } },
            uniquingKeysWith: { first, _ in first }
        )
        let currencyCode = settings.currencyCode
        var rows = openAccounts.compactMap { account -> AccountSpendRowModel? in
            let cents = spendByID[account.id] ?? 0
            let owed = account.kind == .card ? max(0, -account.cachedBalanceCents) : 0
            guard cents > 0 || owed > 0 else { return nil }
            let note = cardNote(for: account, owedCents: owed, currencyCode: currencyCode)
            return AccountSpendRowModel(
                id: account.id,
                name: account.name,
                isCard: account.kind == .card,
                spendCents: cents,
                amountText: CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode),
                note: note.text,
                isPastDue: note.isPastDue
            )
        }
        if let parked = spend.first(where: { $0.accountID == nil }) {
            rows.append(AccountSpendRowModel(
                id: nil, name: "No account", isCard: false, spendCents: parked.cents,
                amountText: CurrencyFormatter.string(
                    fromCents: parked.cents, currencyCode: currencyCode
                ),
                note: "Waiting to be filed", isPastDue: false
            ))
        }
        return rows.sorted { $0.spendCents > $1.spendCents }
    }

    /// The line under a card's name: what it owes and whether that is overdue.
    /// - Parameters:
    ///   - account: The account.
    ///   - owedCents: How much the card owes, zero for a non-card.
    ///   - currencyCode: The display currency.
    /// - Returns: The note, empty for a non-card or a card that owes nothing.
    private func cardNote(
        for account: Domain.Account,
        owedCents: Int,
        currencyCode: String
    ) -> (text: String, isPastDue: Bool) {
        guard account.kind == .card, owedCents > 0 else { return ("", false) }
        let owed = CurrencyFormatter.string(fromCents: owedCents, currencyCode: currencyCode)
        if digest.missedPayments.contains(where: { $0.statement.accountID == account.id }) {
            return ("Owes \(owed) · past due", true)
        }
        if let due = digest.dueSoon.first(where: { $0.statement.accountID == account.id }) {
            let date = due.statement.dueDate.formatted(.dateTime.day().month(.abbreviated))
            return ("Owes \(owed) · due \(date)", false)
        }
        return ("Owes \(owed)", false)
    }
}

/// One slice of the month's category split, with everything already resolved (§7.1).
struct CategorySliceModel: Identifiable, Hashable {
    /// The slice's identity.
    let id: String
    /// The category's name, or "Other" / "Uncategorised".
    let label: String
    /// The category's creation index, which picks its colour.
    let sortIndex: Int
    /// The slice's total in cents.
    let cents: Int
    /// Whether this is the folded remainder rather than a real category.
    let isOther: Bool
}

/// One row in "Spent by account", with every string already rendered (§7.1).
struct AccountSpendRowModel: Identifiable, Hashable {
    /// The account's identifier, `nil` for entries still waiting for one.
    let id: UUID?
    /// The account's name.
    let name: String
    /// Whether the account is a credit card.
    let isCard: Bool
    /// This month's spending through it, in cents.
    let spendCents: Int
    /// That spending, currency-formatted.
    let amountText: String
    /// The line under the name; empty when there is nothing to add.
    let note: String
    /// Whether the card has a missed payment, which reads in red.
    let isPastDue: Bool
}
