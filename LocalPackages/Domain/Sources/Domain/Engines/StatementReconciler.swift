import Foundation

/// What a statement reconcile pass wants written (§4.6).
public struct StatementReconcileOutcome: Equatable, Sendable {
    /// Statements to insert or update.
    public var statements: [CardStatement]
    /// Payment allocations to insert.
    public var payments: [StatementPayment]

    /// Whether the pass found nothing to do.
    public var isEmpty: Bool { statements.isEmpty && payments.isEmpty }

    /// Creates an outcome.
    /// - Parameters:
    ///   - statements: Statements to insert or update.
    ///   - payments: Allocations to insert.
    public init(statements: [CardStatement] = [], payments: [StatementPayment] = []) {
        self.statements = statements
        self.payments = payments
    }
}

/// Brings a card's statements up to date (§4.6).
public enum StatementReconciler {

    /// Generates missing statements, refreshes computed balances, and allocates payments.
    ///
    /// A statement's computed balance is refreshed only while its period is still
    /// open. Once closed the figure is frozen: it is what was owed at closing, and
    /// later charges belong to the next period, not this one.
    ///
    /// - Parameters:
    ///   - account: The card to reconcile.
    ///   - transactions: Every transaction on that card.
    ///   - existingStatements: Statements already stored.
    ///   - existingPayments: Allocations already stored.
    ///   - now: The moment deciding which periods have closed.
    ///   - calendar: The calendar to compute periods in.
    /// - Returns: The statements and allocations to write.
    public static func reconcile(
        account: Account,
        transactions: [Transaction],
        existingStatements: [CardStatement],
        existingPayments: [StatementPayment] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StatementReconcileOutcome {
        guard account.kind == .card else { return StatementReconcileOutcome() }

        var outcome = StatementReconcileOutcome()
        var allStatements: [CardStatement] = []

        for period in StatementEngine.periods(for: account, upTo: now, calendar: calendar) {
            let existing = existingStatements.first { $0.closingDate == period.closingDate }
            var statement = existing ?? CardStatement(
                accountID: account.id,
                periodStart: period.periodStart,
                closingDate: period.closingDate,
                dueDate: period.dueDate
            )
            let hasClosed = period.closingDate <= now
            let computed = StatementEngine.computedBalanceCents(
                account: account, transactions: transactions, closingDate: period.closingDate
            )
            // Freeze the figure at closing; later charges belong to the next period.
            let shouldRefresh = existing == nil || existing?.isPeriodClosed == false
            if shouldRefresh { statement.computedBalanceCents = computed }
            statement.isPeriodClosed = hasClosed

            if existing == nil || existing != statement {
                outcome.statements.append(statement)
            }
            allStatements.append(statement)
        }

        outcome.payments = StatementAllocator.allocate(
            paymentTransactions: transactions.filter { $0.accountID == account.id },
            statements: allStatements,
            existingPayments: existingPayments
        ).payments
        return outcome
    }
}

/// The interest-and-fees prompt shown once per closed statement (§4.6).
///
/// No APR is stored and no interest is calculated: whatever the real statement
/// charged is typed in by hand, and the user's statement is the source of truth.
public enum InterestPrompt {

    /// Whether a statement should ask about interest and fees.
    ///
    /// Asked once on close. Dismissing resolves it, and it never asks again for that
    /// statement.
    ///
    /// - Parameter statement: The statement to test.
    /// - Returns: `true` when the period has closed and the prompt is unresolved.
    public static func shouldAsk(about statement: CardStatement) -> Bool {
        statement.isPeriodClosed && !statement.interestPromptResolved
    }

    /// Marks a statement's prompt as answered or dismissed.
    /// - Parameter statement: The statement to resolve.
    /// - Returns: The statement with the prompt resolved.
    public static func resolved(_ statement: CardStatement) -> CardStatement {
        var resolved = statement
        resolved.interestPromptResolved = true
        return resolved
    }

    /// Builds the expense recording interest or fees on a card.
    ///
    /// Dated to the closing date and categorised Bills, so it lands in the period the
    /// card actually charged it.
    ///
    /// - Parameters:
    ///   - statement: The statement being charged.
    ///   - cents: The amount the real statement charged.
    ///   - billsCategoryID: The Bills category to file it under.
    /// - Returns: The expense, or `nil` when the amount is not positive.
    public static func makeCharge(
        for statement: CardStatement,
        cents: Int,
        billsCategoryID: UUID?
    ) -> Transaction? {
        guard cents > 0, let accountID = statement.accountID else { return nil }
        return Transaction(
            amountCents: cents,
            type: .expense,
            categoryID: billsCategoryID,
            accountID: accountID,
            date: statement.closingDate,
            merchant: "Interest and fees"
        )
    }
}
