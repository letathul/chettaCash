import Foundation

/// Why a transfer could not be built.
public enum TransferError: Error, Equatable, Sendable {
    /// Source and destination accounts were the same (§4.3).
    case sameAccount
    /// The amount was zero or negative.
    case nonPositiveAmount
}

/// Builds the two legs of a transfer (§4.3).
///
/// A transfer is always two transactions sharing a `transferGroupID`: an outflow on
/// the source account and an inflow on the destination. Both legs carry the same
/// amount and date, and neither carries a category. The rule that editing or
/// deleting one leg affects both is a repository contract, not a factory concern —
/// see ``TransactionRepository``.
public enum TransferFactory {

    /// Builds the outflow and inflow legs of a transfer.
    ///
    /// - Parameters:
    ///   - amountCents: The amount to move, which must be positive.
    ///   - date: The date both legs carry.
    ///   - sourceAccountID: The account money leaves.
    ///   - destinationAccountID: The account money arrives in, which must differ
    ///     from the source.
    ///   - merchant: Optional label carried by both legs.
    ///   - memo: Optional note carried by both legs.
    /// - Returns: The outflow and inflow legs, sharing one `transferGroupID`.
    /// - Throws: ``TransferError/nonPositiveAmount`` when `amountCents` is not
    ///   positive, or ``TransferError/sameAccount`` when source and destination match.
    public static func makeLegs(
        amountCents: Int,
        date: Date,
        sourceAccountID: UUID,
        destinationAccountID: UUID,
        merchant: String = "",
        memo: String? = nil
    ) throws -> (out: Transaction, in: Transaction) {
        guard amountCents > 0 else { throw TransferError.nonPositiveAmount }
        guard sourceAccountID != destinationAccountID else { throw TransferError.sameAccount }

        let groupID = UUID()
        let outLeg = Transaction(
            amountCents: amountCents,
            type: .transferOut,
            categoryID: nil,
            accountID: sourceAccountID,
            date: date,
            merchant: merchant,
            memo: memo,
            transferGroupID: groupID
        )
        let inLeg = Transaction(
            amountCents: amountCents,
            type: .transferIn,
            categoryID: nil,
            accountID: destinationAccountID,
            date: date,
            merchant: merchant,
            memo: memo,
            transferGroupID: groupID
        )
        return (outLeg, inLeg)
    }
}

/// Builds balance-correction transactions (§4.4).
///
/// An adjustment affects balances and Net Worth but is excluded from spend and
/// income totals, because a correction is not spending. Use this when the derived
/// balance has drifted from reality; when the starting figure was simply wrong,
/// edit the account's opening balance instead.
public enum AdjustmentFactory {

    /// Builds a balance-correction transaction.
    ///
    /// - Parameters:
    ///   - accountID: The account whose balance is being corrected.
    ///   - signedCents: The correction to apply, negative to reduce the balance.
    ///   - date: When the correction takes effect.
    ///   - memo: Optional note explaining the correction.
    /// - Returns: An `adjustment` transaction carrying the signed correction.
    public static func make(
        accountID: UUID,
        signedCents: Int,
        date: Date = .now,
        memo: String? = nil
    ) -> Transaction {
        Transaction(
            amountCents: abs(signedCents),
            type: .adjustment,
            signedOverrideCents: signedCents,
            categoryID: SystemCategoryID.balanceAdjustment,
            accountID: accountID,
            date: date,
            memo: memo
        )
    }
}
