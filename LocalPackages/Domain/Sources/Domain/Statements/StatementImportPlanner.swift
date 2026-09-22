import Foundation

/// What the app already holds when a statement is imported, which the planner reads
/// but never changes.
public struct StatementImportContext: Sendable {
    /// The card the statement belongs to.
    public var accountID: UUID
    /// Every transaction already recorded against that card in the relevant window.
    public var existing: [Transaction]
    /// The merchant pins that decide categories, consulted before anything else.
    public var pins: [MerchantCategoryRule]
    /// The categories an expense may be filed under.
    public var selectableCategories: [Category]
    /// The calendar deciding which day a date falls on.
    public var calendar: Calendar
    /// How many days either side of a row's date still count as the same purchase.
    ///
    /// Three by default. A statement's posting date routinely lags the day the user typed,
    /// and a purchase made on a Friday posts on the Monday — three days. Requiring an exact
    /// day would report a false new row for most of the duplicates this feature exists to
    /// catch, and requiring one day would still miss every weekend.
    public var dayTolerance: Int

    /// Creates a context.
    /// - Parameters:
    ///   - accountID: The card the statement belongs to.
    ///   - existing: Transactions already recorded against that card.
    ///   - pins: The merchant pins.
    ///   - selectableCategories: The selectable expense categories.
    ///   - calendar: The calendar deciding day boundaries.
    ///   - dayTolerance: Days either side that still count as the same purchase.
    public init(
        accountID: UUID,
        existing: [Transaction] = [],
        pins: [MerchantCategoryRule] = [],
        selectableCategories: [Category] = [],
        calendar: Calendar = .current,
        dayTolerance: Int = 3
    ) {
        self.accountID = accountID
        self.existing = existing
        self.pins = pins
        self.selectableCategories = selectableCategories
        self.calendar = calendar
        self.dayTolerance = dayTolerance
    }
}

/// Decides what importing a statement would write, before anything is written (§4.2).
///
/// Pure and synchronous, like ``QuickExpensePlanner`` and ``StatementReconciler``: every
/// decision is testable without a database, a simulator or a language model.
///
/// Three outcomes per row, and the order matters. A row the ledger already records — same
/// card, amount and merchant, within a few days — is dropped silently; that is the same
/// purchase and needs no one's attention. A row whose card and amount match but whose
/// **wording** does not becomes a conflict for the user. Everything else is new.
///
/// **Matching is by count, not by existence.** Each ledger entry can answer only one row
/// (see ``ExistingIndex``), so a statement listing a charge twice against one recorded entry
/// still writes the second — a bank printing a line twice is reporting two purchases, not
/// making a mistake — while an import can never write more rows than the statement holds.
public enum StatementImportPlanner {

    /// The tag every imported transaction carries, mirroring ``QuickExpensePlanner/originTag``.
    ///
    /// It makes an import findable in Search afterwards, and undoable by hand, which matters
    /// more here than for a single Shortcut entry because one import writes dozens of rows.
    public static let originTag = "statement"

    /// Sorts every row of a statement into what to write, what to ask about, and what to drop.
    /// - Parameters:
    ///   - document: The statement as read.
    ///   - context: What the app already holds.
    /// - Returns: The plan.
    public static func plan(
        _ document: StatementDocument,
        in context: StatementImportContext
    ) -> ImportPlan {
        // The *source* count, not the parsed count: a summary derived from the rows that
        // survived parsing can never report that anything went missing.
        var plan = ImportPlan(
            unread: document.unread, rowsProcessed: document.sourceLineCount
        )
        var index = ExistingIndex(context: context)

        for row in document.rows {
            guard row.kind != .payment else {
                plan.skipped.append(SkippedRow(row: row, reason: .cardPayment))
                continue
            }
            guard row.amountCents > 0 else {
                plan.skipped.append(SkippedRow(row: row, reason: .unreadableAmount))
                continue
            }

            let candidate = transaction(from: row, in: context)

            if index.claimSameMerchant(candidate, in: context) != nil {
                plan.skipped.append(SkippedRow(row: row, reason: .exactDuplicate))
            } else if let match = index.claimDifferentMerchant(candidate, in: context) {
                plan.conflicts.append(
                    DuplicateConflict(
                        incoming: candidate, row: row, existing: match.transaction,
                        reason: match.reason
                    )
                )
            } else {
                plan.additions.append(candidate)
            }
        }
        return plan
    }

    /// Builds the transaction a row would become.
    ///
    /// The category is resolved pin-first then from history — the same precedence
    /// ``QuickExpensePlanner`` uses, and free, because both answers come from what the user
    /// has already decided rather than from a guess.
    ///
    /// - Parameters:
    ///   - row: The statement row.
    ///   - context: What the app already holds.
    /// - Returns: The candidate transaction.
    static func transaction(
        from row: StatementRow,
        in context: StatementImportContext
    ) -> Transaction {
        Transaction(
            amountCents: row.amountCents,
            type: row.kind == .refund ? .income : .expense,
            categoryID: categoryID(for: row.merchant, in: context),
            accountID: context.accountID,
            date: row.date,
            merchant: row.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            memo: memo(for: row),
            tags: [originTag]
        )
    }

    /// The note kept when a reader rewrote the merchant name.
    ///
    /// The statement's own wording is what the user can check against their bank, so it is
    /// never simply discarded in favour of a tidied name.
    ///
    /// - Parameter row: The statement row.
    /// - Returns: The memo, or `nil` when the name was not rewritten.
    private static func memo(for row: StatementRow) -> String? {
        guard let cleaned = row.cleanedMerchant,
              cleaned != row.rawDescriptor else { return nil }
        return "Statement: \(row.rawDescriptor)"
    }

    /// The category a merchant should land in.
    /// - Parameters:
    ///   - merchant: The merchant name.
    ///   - context: What the app already holds.
    /// - Returns: The category's identifier, or `nil` when nothing decides it.
    private static func categoryID(
        for merchant: String,
        in context: StatementImportContext
    ) -> UUID? {
        let key = MerchantCategoryIndex.key(for: merchant)
        if !key.isEmpty,
           let pin = context.pins.first(where: { $0.merchantKey == key }),
           !SystemCategoryID.isSystem(pin.categoryID),
           context.selectableCategories.contains(where: { $0.id == pin.categoryID }) {
            return pin.categoryID
        }
        let learned = MerchantCategoryIndex.categoryID(for: merchant, in: context.existing)
        guard let learned,
              context.selectableCategories.contains(where: { $0.id == learned }) else { return nil }
        return learned
    }
}
