import AppIntents
import Foundation
import Domain

/// What every "log something without opening the app" intent has in common (§15).
///
/// Add Expense and Log Income differ in one field — which way the money moved — and in the
/// words they say. Everything else is identical: the same account resolution, the same
/// planner, the same duplicate guard, the same single-commit write, the same report. Stating
/// that once is what keeps the two from drifting apart, which is the usual fate of a second
/// intent written by copying the first.
///
/// The parameters stay on the conforming types. `@Parameter` is a property wrapper and the
/// system reads the declarations off each intent directly, so they cannot be inherited — but
/// they can be *required*, which is what this does.
///
/// Not `@MainActor` as a whole, for the same reason ``AddExpenseIntent`` is not: the system
/// reads an intent's static requirements off the main actor. Isolation is declared per
/// method instead, which also keeps `receiptPages()` off the main actor where it belongs.
protocol QuickEntryIntent: AppIntent {
    /// Which way the money moves.
    static var entryType: Domain.TransactionType { get }
    /// The categories this kind of entry may be filed under.
    static var categoryContext: CategoryContext { get }

    /// How much, in the app's single currency.
    var amount: Double { get }
    /// Who it was with.
    var merchant: String { get }
    /// The category, as free text.
    var category: String? { get }
    /// The account chosen in the editor, if one was.
    var account: AccountEntity? { get }
    /// The account number supplied as text.
    var accountNumber: String? { get }
    /// The account name supplied as text.
    var accountName: String? { get }
    /// When it happened.
    var date: Date? { get }
    /// User labels, before the origin tag is added.
    var tags: [String]? { get }
    /// Receipt images or PDFs.
    var receipts: [IntentFile]? { get }
    /// Where it happened.
    var location: String? { get }
    /// A free-text note.
    var memo: String? { get }
    /// Whether to file this merchant under the same category next time.
    var rememberCategory: Bool { get }
    /// Whether to record this even when an identical entry was logged moments ago.
    var allowsDuplicate: Bool { get }

    /// Asks the user which account, when nothing else names one.
    ///
    /// A protocol requirement because it goes through `$account`, the projected value of a
    /// property wrapper, which only the conforming type can reach.
    ///
    /// - Returns: The chosen account, or `nil` when the user gave none.
    /// - Throws: The framework's own request, so it can present the picker.
    @MainActor
    func requestAccount() async throws -> AccountEntity?
}

/// What one run of a quick entry produced.
struct QuickEntryOutcome {
    /// The entry, as the Shortcuts app sees it.
    let entity: TransactionEntity
    /// What to say about it.
    let dialog: IntentDialog
}

/// The whole of a quick entry, shared by every intent that records one.
extension QuickEntryIntent {

    /// Records the entry and works out what to say about it.
    ///
    /// The order is load-bearing: validate the amount, settle the account, plan everything
    /// the entry implies, check it is not a repeat, and only then write. Nothing before the
    /// write touches the store, so a refusal anywhere in the first four steps leaves it
    /// exactly as it was.
    ///
    /// - Returns: The entry and the sentence to say.
    /// - Throws: ``QuickEntryError`` when the input cannot be used, or a persistence error if
    ///   a write fails.
    @MainActor
    func record() async throws -> QuickEntryOutcome {
        let dependencies = try await AppEnvironment.shared()
        let amountCents = try centsFromAmount()
        let resolved = try await resolveAccount(dependencies: dependencies)
        let plan = try await makePlan(
            amountCents: amountCents, accountID: resolved.id, dependencies: dependencies
        )
        let formatted = CurrencyFormatter.string(
            fromCents: amountCents, currencyCode: dependencies.settings.currencyCode
        )
        let place = place(plan, fallingBackTo: resolved.name)

        // Checked before anything is written, and answered rather than refused: an error
        // makes an automation look broken where "that's already logged" is simply true.
        if let existing = try await duplicate(of: plan.transaction, dependencies: dependencies) {
            return try await outcome(
                for: existing,
                report: QuickEntryReport(wasAlreadyLogged: true),
                phrasing: .init(
                    amount: formatted, place: place, date: existing.date, type: Self.entryType
                ),
                dependencies: dependencies
            )
        }

        try await commit(plan, newAccount: resolved.created, dependencies: dependencies)
        NotificationCenter.default.post(name: .chettaCashDataDidChange, object: nil)

        return try await outcome(
            for: plan.transaction,
            report: QuickEntryReport(
                createdAccountName: resolved.created?.name,
                parkedReason: resolved.doubt,
                isPosted: BalanceEngine.isPosted(plan.transaction),
                pinnedCategoryLabel: try await pinnedLabel(for: plan, dependencies: dependencies)
            ),
            phrasing: .init(
                amount: formatted,
                place: place,
                date: plan.transaction.date,
                type: Self.entryType
            ),
            dependencies: dependencies
        )
    }

    /// The entry and the sentence, once both are decided.
    /// - Parameters:
    ///   - transaction: The entry to hand back.
    ///   - report: What the run did beyond the obvious.
    ///   - phrasing: The parts of the entry to say.
    ///   - dependencies: The app's dependency graph.
    /// - Returns: The outcome.
    /// - Throws: A persistence error if a fetch fails.
    @MainActor
    private func outcome(
        for transaction: Domain.Transaction,
        report: QuickEntryReport,
        phrasing: QuickEntryDialog.Phrasing,
        dependencies: AppDependencies
    ) async throws -> QuickEntryOutcome {
        QuickEntryOutcome(
            entity: try await entity(for: transaction, dependencies: dependencies),
            dialog: IntentDialog(
                stringLiteral: QuickEntryDialog.text(for: report, phrasing: phrasing)
            )
        )
    }

    /// Where the entry happened, for the spoken result.
    ///
    /// The merchant, unless it is bare — in which case the account is the only thing left
    /// that says anything about it, and a parked entry has not even got that.
    ///
    /// - Parameters:
    ///   - plan: What was written.
    ///   - accountName: The account's name, which may be empty.
    /// - Returns: The place.
    func place(_ plan: QuickExpensePlan, fallingBackTo accountName: String) -> String {
        if !plan.transaction.merchant.isEmpty { return plan.transaction.merchant }
        return accountName.isEmpty ? "no merchant" : accountName
    }

    /// The label of a pin this run created, if it created one.
    ///
    /// ``QuickExpensePlan/newPin`` says a pin was written but carries only its category's
    /// identifier, and the pin is exactly the kind of standing decision that has to be said
    /// out loud once — it outranks whatever every later run of this Shortcut passes.
    ///
    /// - Parameters:
    ///   - plan: What was written.
    ///   - dependencies: The app's dependency graph.
    /// - Returns: The category's label, or `nil` when no pin was created.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func pinnedLabel(
        for plan: QuickExpensePlan,
        dependencies: AppDependencies
    ) async throws -> String? {
        guard let pin = plan.newPin else { return nil }
        if let created = plan.newCategory, created.id == pin.categoryID { return created.label }
        let categories = try await dependencies.categories
            .selectableCategories(context: Self.categoryContext)
        return categories.first { $0.id == pin.categoryID }?.label
    }

    /// One stored entry, as the Shortcuts app sees it.
    /// - Parameters:
    ///   - transaction: The entry to describe.
    ///   - dependencies: The app's dependency graph.
    /// - Returns: The entity.
    /// - Throws: A persistence error if a fetch fails.
    @MainActor
    func entity(
        for transaction: Domain.Transaction,
        dependencies: AppDependencies
    ) async throws -> TransactionEntity {
        let built = try await TransactionEntityBuilder(dependencies: dependencies)
            .entities(for: [transaction])
        return built.first ?? TransactionEntity(
            transaction: transaction,
            accountName: "",
            categoryLabel: "",
            currencyCode: dependencies.settings.currencyCode
        )
    }
}
