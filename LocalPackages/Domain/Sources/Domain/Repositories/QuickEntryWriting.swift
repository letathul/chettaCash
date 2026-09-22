import Foundation

/// Everything one quick entry writes, so it commits once or not at all (§15).
///
/// A Shortcut can imply as many as four rows: a card it created, a category it invented, the
/// entry itself, and a merchant pin. Written through four repositories that is four separate
/// commits — each `@ModelActor` has its own context — so a failure at the third leaves an
/// orphan account and an orphan category behind, in a process that is about to end with no
/// window to say so in.
public struct QuickEntryWrite: Sendable {
    /// The entry itself.
    public var transaction: Transaction
    /// An account to create, when the entry's card did not exist yet.
    public var newAccount: Account?
    /// A category to create, when the entry named one that did not exist yet.
    public var newCategory: Category?
    /// A merchant pin to write, when the entry asked for one.
    public var newPin: MerchantCategoryRule?

    /// Creates a bundle.
    /// - Parameters:
    ///   - transaction: The entry itself.
    ///   - newAccount: An account to create, if any.
    ///   - newCategory: A category to create, if any.
    ///   - newPin: A merchant pin to write, if any.
    public init(
        transaction: Transaction,
        newAccount: Account? = nil,
        newCategory: Category? = nil,
        newPin: MerchantCategoryRule? = nil
    ) {
        self.transaction = transaction
        self.newAccount = newAccount
        self.newCategory = newCategory
        self.newPin = newPin
    }
}

/// Writes a quick entry as one unit of work (§15).
///
/// Implementations must commit all of a ``QuickEntryWrite`` or none of it, and must uphold
/// the same rules the individual repositories do: upsert the account, category and
/// transaction on `id`, upsert the pin on `merchantKey` (§4.8), and rebuild the account's
/// balance cache from its own history rather than trusting what the caller supplied.
public protocol QuickEntryWriting: Sendable {
    /// Writes everything one quick entry implies, in one commit.
    /// - Parameter bundle: What to write.
    /// - Throws: ``TransactionRepositoryError/unknownAccount(_:)`` when the entry names an
    ///   account that neither exists nor is being created, or a persistence error if the
    ///   write fails. Nothing is committed in either case.
    func write(_ bundle: QuickEntryWrite) async throws
}
