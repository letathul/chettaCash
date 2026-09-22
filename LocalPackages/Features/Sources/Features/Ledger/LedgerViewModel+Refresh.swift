import Foundation
import Domain

/// Rebuilding the Ledger's derived state (§7.4).
///
/// Split from ``LedgerViewModel`` to keep each file within the 300-line limit.
extension LedgerViewModel {

    /// Recomputes every derived value in one pass.
    ///
    /// Call after the data changes, after the filter changes, and after the display
    /// currency changes — the row models carry formatted amounts, so a currency switch
    /// invalidates them just as a filter change does.
    ///
    /// The pipeline runs exactly once here: filter, assemble, split. Each stage feeds
    /// the next rather than being re-derived by whichever property asked for it.
    public func refresh() {
        accountsByID = Dictionary(
            accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        categoriesByID = Dictionary(
            categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let selectable = categories.filter {
            !$0.isArchived && !SystemCategoryID.isSystem($0.id)
        }
        categoriesByContext = Dictionary(grouping: selectable, by: \.context)
        // The filter row offers only categories some transaction actually carries, plus
        // whichever one is selected, so an active filter can never become invisible. The
        // *picker* above keeps the full list: a category nothing uses yet must still be
        // choosable, or it could never come to be used.
        let usedCategoryIDs = Set(allTransactions.compactMap(\.categoryID))
        let selectedCategoryID = filter.categoryID
        filterCategories = selectable.filter {
            usedCategoryIDs.contains($0.id) || $0.id == selectedCategoryID
        }
        selectableAccounts = accounts.filter { !$0.isClosed }

        filteredTransactions = filter.apply(to: allTransactions)
        items = LedgerAssembler.items(
            from: filteredTransactions,
            collapseTransfers: !filter.isAccountFiltered
        )
        let split = LedgerAssembler.split(items)
        upcomingItems = split.upcoming
        isFilteredToZero = !allTransactions.isEmpty && items.isEmpty

        spendCents = TotalsEngine.spendTotalCents(transactions: filteredTransactions)
        incomeCents = TotalsEngine.incomeTotalCents(transactions: filteredTransactions)
        netCents = TotalsEngine.netTotalCents(transactions: filteredTransactions)
        bannerCount = LedgerAssembler.bannerCount(of: filteredTransactions)
        scopeLabel = makeScopeLabel()

        let currencyCode = settings.currencyCode
        upcomingRows = split.upcoming.map { row(for: $0, currencyCode: currencyCode) }
        postedDays = LedgerAssembler.groupedByDay(split.posted).map { group in
            LedgerDay(
                day: group.day,
                rows: group.items.map { row(for: $0, currencyCode: currencyCode) }
            )
        }
    }

    /// Renders one row's content.
    ///
    /// Internal rather than private: the search screen renders its transaction results
    /// with the same row models, so that a result and a Ledger row cannot read
    /// differently (§7.12).
    ///
    /// - Parameters:
    ///   - item: The row to render.
    ///   - currencyCode: The display currency.
    /// - Returns: The row model.
    func row(for item: LedgerItem, currencyCode: String) -> LedgerRowModel {
        LedgerRowModel(
            id: item.id,
            title: title(for: item),
            subtitle: subtitle(for: item),
            amountText: amountText(for: item, currencyCode: currencyCode),
            tone: tone(for: item),
            glyph: glyph(for: item),
            avatar: avatar(for: item),
            isRecurring: item.editableTransaction.recurringRuleID != nil,
            isEditable: isEditable(item),
            editableTransaction: item.editableTransaction
        )
    }

    /// The row's primary line.
    /// - Parameter item: The row to describe.
    /// - Returns: A merchant name, or "Chequing → Visa" for a collapsed transfer.
    private func title(for item: LedgerItem) -> String {
        switch item {
        case .transfer(let outLeg, let inLeg):
            let source = account(id: outLeg.accountID)?.name ?? "Unknown"
            let destination = account(id: inLeg.accountID)?.name ?? "Unknown"
            return "\(source) → \(destination)"
        case .single(let transaction):
            if transaction.merchant.isEmpty {
                return transaction.type == .adjustment ? "Balance adjustment" : "No merchant"
            }
            return transaction.merchant
        }
    }

    /// The "Category · Account" subline.
    /// - Parameter item: The row to describe.
    /// - Returns: The subline.
    private func subtitle(for item: LedgerItem) -> String {
        switch item {
        case .transfer:
            return "Transfer"
        case .single(let transaction):
            let accountName = account(id: transaction.accountID)?.name ?? "No account"
            guard transaction.type != .adjustment else { return "Adjustment · \(accountName)" }
            let label = category(id: transaction.categoryID)?.label
                ?? (transaction.transferGroupID != nil ? "Transfer" : "Uncategorised")
            return "\(label) · \(accountName)"
        }
    }

    /// The signed, formatted amount.
    ///
    /// A collapsed transfer shows a bare magnitude: it is neither money in nor money
    /// out, and signing it would pick one of the two legs arbitrarily.
    ///
    /// - Parameters:
    ///   - item: The row to describe.
    ///   - currencyCode: The display currency.
    /// - Returns: The amount text.
    private func amountText(for item: LedgerItem, currencyCode: String) -> String {
        switch item {
        case .transfer(let outLeg, _):
            return CurrencyFormatter.string(
                fromCents: outLeg.amountCents, currencyCode: currencyCode
            )
        case .single(let transaction):
            let cents = BalanceEngine.signedAmountCents(for: transaction)
            let magnitude = CurrencyFormatter.string(
                fromCents: abs(cents), currencyCode: currencyCode
            )
            return (cents < 0 ? "−" : "+") + magnitude
        }
    }

    /// Income reads green, outflows read primary, transfers stay neutral.
    /// - Parameter item: The row to describe.
    /// - Returns: The tone.
    private func tone(for item: LedgerItem) -> AmountTone {
        guard case .single(let transaction) = item else { return .secondary }
        return transaction.type == .income ? .positive : .primary
    }

    /// The SF Symbol drawn inside the avatar.
    /// - Parameter item: The row to describe.
    /// - Returns: An SF Symbol name.
    private func glyph(for item: LedgerItem) -> String {
        switch item {
        case .transfer: return "arrow.left.arrow.right"
        case .single(let transaction):
            switch transaction.type {
            case .income: return "arrow.down.left"
            case .adjustment: return "slider.horizontal.3"
            case .transferIn, .transferOut: return "arrow.left.arrow.right"
            case .expense: return "arrow.up.right"
            }
        }
    }

    /// The avatar's tint.
    /// - Parameter item: The row to describe.
    /// - Returns: The avatar.
    private func avatar(for item: LedgerItem) -> RowAvatar {
        switch item {
        case .transfer:
            return .neutral
        case .single(let transaction):
            if transaction.type == .income { return .income }
            guard let category = category(id: transaction.categoryID) else { return .neutral }
            return .category(label: category.label, sortIndex: category.sortIndex)
        }
    }

    /// The label describing the current period and account scope.
    /// - Returns: The label.
    private func makeScopeLabel() -> String {
        let period: String
        switch filter.period {
        case .thisMonth: period = "This month"
        case .lastMonth: period = "Last month"
        case .allTime: period = "All time"
        }
        guard let accountID = filter.accountID, let account = account(id: accountID) else {
            return "\(period) · All accounts"
        }
        return "\(period) · \(account.name)"
    }
}
