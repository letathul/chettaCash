import Foundation
import Domain

/// Applies ``StatementImportPlanner`` decisions to the stores (§4.2).
///
/// The same shape as ``StatementCoordinator``: it holds the repository protocols, calls a
/// pure Domain engine, and writes what the engine decided. No import rule lives here —
/// everything decidable is decided in Domain, where it is tested without a store.
@MainActor
public struct StatementImportCoordinator {

    /// Reads and writes accounts.
    private let accounts: any AccountRepository
    /// Reads and writes transactions.
    private let transactions: any TransactionRepository
    /// Supplies the categories an imported row may be filed under.
    private let categories: any CategoryRepository
    /// Supplies the merchant pins that decide categories.
    private let merchantRules: (any MerchantCategoryRuleRepository)?

    /// Creates the coordinator.
    /// - Parameters:
    ///   - accounts: Reads and writes accounts.
    ///   - transactions: Reads and writes transactions.
    ///   - categories: Supplies selectable categories.
    ///   - merchantRules: Supplies merchant pins, when the app wires them.
    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        merchantRules: (any MerchantCategoryRuleRepository)? = nil
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.categories = categories
        self.merchantRules = merchantRules
    }

    /// The open accounts an import could be filed against.
    /// - Returns: The accounts, in sort order.
    /// - Throws: A persistence error if the fetch fails.
    public func openAccounts() async throws -> [Domain.Account] {
        try await accounts.accounts(includeClosed: false)
    }

    /// Works out which card a statement belongs to.
    /// - Parameters:
    ///   - document: The statement as read.
    ///   - now: The date a created card's opening balance would apply from.
    /// - Returns: What was found, and a card to create when creating one is safe.
    /// - Throws: A persistence error if the fetch fails.
    public func resolveAccount(
        for document: StatementDocument,
        now: Date = .now
    ) async throws -> StatementAccountMatch {
        let all = try await accounts.accounts(includeClosed: true)
        let groups = try await accounts.groups()
        return StatementAccountProvisioner.resolve(
            document.tender,
            in: all,
            groupID: groups.first?.id,
            sortIndex: all.count,
            openingDate: document.periodStart ?? now
        )
    }

    /// The categories an imported row may be filed under.
    ///
    /// Exposed so the review screen's row editors can offer them: the planner already reads
    /// the same list to decide a row's category, and two sources would drift.
    ///
    /// - Returns: The selectable expense categories.
    /// - Throws: A persistence error if the fetch fails.
    public func selectableCategories() async throws -> [Domain.Category] {
        try await categories.selectableCategories(context: .expense)
    }

    /// Creates a card a statement named but the user had not set up.
    /// - Parameter account: The card to create.
    /// - Throws: A persistence error if the write fails.
    public func create(_ account: Domain.Account) async throws {
        try await accounts.save(account)
    }

    /// Decides what importing a statement would write.
    /// - Parameters:
    ///   - document: The statement as read.
    ///   - accountID: The card to import against.
    ///   - calendar: The calendar deciding which day a date falls on.
    /// - Returns: The plan.
    /// - Throws: A persistence error if a fetch fails.
    public func plan(
        _ document: StatementDocument,
        accountID: UUID,
        calendar: Calendar = .current
    ) async throws -> ImportPlan {
        async let history = transactions.transactions(
            accountID: accountID, in: Self.window(for: document, calendar: calendar)
        )
        async let selectable = categories.selectableCategories(context: .expense)
        async let pins = merchantRules?.rules() ?? []

        let context = StatementImportContext(
            accountID: accountID,
            existing: try await history,
            pins: try await pins,
            selectableCategories: try await selectable,
            calendar: calendar
        )
        return StatementImportPlanner.plan(document, in: context)
    }

    /// Writes a plan's additions in one store write.
    /// - Parameter plan: The plan to apply.
    /// - Throws: A persistence error if the write fails.
    public func commit(_ plan: ImportPlan) async throws {
        guard !plan.additions.isEmpty else { return }
        try await transactions.saveAll(plan.additions)
    }

    /// Writes one transaction resolved out of the conflict wizard.
    /// - Parameter transaction: The transaction to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ transaction: Domain.Transaction) async throws {
        try await transactions.save(transaction)
    }

    /// Removes a transaction the user decided was a duplicate.
    /// - Parameter id: The transaction's identifier.
    /// - Throws: A persistence error if the delete fails.
    public func delete(id: UUID) async throws {
        try await transactions.delete(id: id)
    }

    /// The date range a statement's rows could possibly duplicate.
    ///
    /// Narrowed to the statement's own span plus the planner's day tolerance, so importing
    /// one month does not fetch a card's entire history — which on a well-used card is
    /// thousands of rows to compare a few dozen against.
    ///
    /// - Parameters:
    ///   - document: The statement as read.
    ///   - calendar: The calendar to widen the range in.
    /// - Returns: The range, or `nil` when the statement has no rows.
    static func window(
        for document: StatementDocument,
        calendar: Calendar
    ) -> ClosedRange<Date>? {
        let dates = document.rows.map(\.date)
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        // Two days either side: one for the planner's tolerance, one so a row sitting on a
        // day boundary is not excluded by the fetch before it can be compared.
        guard let from = calendar.date(byAdding: .day, value: -2, to: earliest),
              let until = calendar.date(byAdding: .day, value: 2, to: latest) else { return nil }
        return from...until
    }
}
