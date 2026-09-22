import Foundation

/// What a repository refuses to write, and why.
///
/// Gathered here rather than beside each protocol so the shapes can be compared. They share
/// one rule: a row whose relationship cannot be resolved is **refused**, never written with
/// the relationship silently left empty. A row that looks filed but is not still appears in
/// every list and still counts toward every total, while nothing it points at reflects it —
/// which is worse than a refusal, because a refusal says so.

/// Why a transaction could not be written.
public enum TransactionRepositoryError: Error, Equatable, Sendable {
    /// The transaction named an account that does not exist.
    ///
    /// Refused rather than silently orphaning the row. A `nil` ``Transaction/accountID``
    /// never reaches this — an unassigned entry is legal (§15.5); an entry pointing at a
    /// vanished account is not.
    case unknownAccount(UUID)
}

/// Why a product could not be written.
public enum ProductRepositoryError: Error, Equatable, Sendable {
    /// The product pointed at a transaction that does not exist.
    ///
    /// A product with no purchase is not representable (§7.8), so the write is refused
    /// rather than silently orphaning the row.
    case unknownTransaction(UUID)
}
