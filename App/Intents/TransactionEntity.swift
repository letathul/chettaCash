import AppIntents
import Foundation
import UIKit
import Domain

/// One ledger entry, as the Shortcuts app sees it (§15).
///
/// Exists so a Shortcut can carry on with what it just recorded, or with what Find
/// Transactions turned up, rather than only hearing that it happened. Nothing in the app
/// takes one back as a parameter: these travel outward, into whatever the Shortcut does next.
///
/// ``amount`` is a `Double`, which is the one place that is allowed: it is a value leaving
/// the app for a Shortcut to do arithmetic with, and it never comes back. Money inside the
/// app is `Int` cents and stays that way (§2).
struct TransactionEntity: AppEntity {
    /// The entry's identifier, shared with ``Domain/Transaction``.
    let id: UUID

    /// How much it was for, in the app's single currency.
    @Property(title: "Amount")
    var amount: Double

    /// Who it was with.
    @Property(title: "Merchant")
    var merchant: String

    /// When it happened.
    @Property(title: "Date")
    var date: Date

    /// The account it is recorded against, or empty for a parked entry (§15.5).
    @Property(title: "Account")
    var accountName: String

    /// The category it is filed under, or empty when it has none.
    @Property(title: "Category")
    var categoryLabel: String

    /// The amount already rendered in the user's currency, for display and for speech.
    let formattedAmount: String

    /// How the type is described in the Shortcuts editor.
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Transaction" }

    /// Resolves an entry by identifier.
    ///
    /// Deliberately an `EntityQuery` and not an `EntityStringQuery`: there is no search
    /// across the ledger here, so nothing can be enumerated out of the app by asking. A
    /// caller that holds an identifier already had it handed to them by a run of their own,
    /// and this only re-resolves it when the system needs the entity again later.
    static let defaultQuery = TransactionEntityQuery()

    /// How one entry is shown in the Shortcuts editor.
    var displayRepresentation: DisplayRepresentation {
        let title = merchant.isEmpty ? "Transaction" : merchant
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(formattedAmount) · \(date.formatted(.dateTime.day().month(.abbreviated)))"
        )
    }

    /// Builds an entity from a stored entry.
    /// - Parameters:
    ///   - transaction: The entry.
    ///   - accountName: The account's name, or empty for a parked entry.
    ///   - categoryLabel: The category's label, or empty when it has none.
    ///   - currencyCode: The code every figure renders in (§5.1).
    init(
        transaction: Domain.Transaction,
        accountName: String,
        categoryLabel: String,
        currencyCode: String
    ) {
        // The plain stored properties first: assigning a `@Property` goes through its
        // wrapper, which touches `self`, and `self` is not whole until these two are set.
        self.id = transaction.id
        self.formattedAmount = CurrencyFormatter.string(
            fromCents: transaction.amountCents, currencyCode: currencyCode
        )
        self.date = transaction.date
        self.merchant = transaction.merchant
        self.accountName = accountName
        self.categoryLabel = categoryLabel
        self.amount = Double(transaction.amountCents) / 100
    }
}

/// Finds a ledger entry a Shortcut already holds.
struct TransactionEntityQuery: EntityQuery {

    /// Fetches entries by identifier.
    ///
    /// Withheld entirely while the phone is locked and the §11 lock is on. Unlike
    /// ``AccountEntityQuery/entities(for:)``, which merely confirms a name the caller already
    /// has, this hands back an amount — and an amount is exactly what the lock is for
    /// (§15.3).
    ///
    /// - Parameter identifiers: The identifiers to fetch.
    /// - Returns: The matching entries.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TransactionEntity] {
        let dependencies = try await AppEnvironment.shared()
        guard !ShortcutPrivacyPolicy.hidesStoredData(
            lockEnabled: dependencies.settings.appLockEnabled,
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
        ) else { return [] }

        let wanted = Set(identifiers)
        let stored = try await dependencies.transactions.transactions(accountID: nil, in: nil)
            .filter { wanted.contains($0.id) }
        guard !stored.isEmpty else { return [] }
        return try await TransactionEntityBuilder(dependencies: dependencies)
            .entities(for: stored)
    }
}
