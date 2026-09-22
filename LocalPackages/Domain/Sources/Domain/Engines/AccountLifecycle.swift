import Foundation

/// Why an account cannot be closed yet (§4.7).
public enum CloseBlocker: Equatable, Sendable {
    /// The account still holds money that must be moved out first.
    case holdsBalance(cents: Int)
    /// The card still owes money that must be paid off first.
    case owesBalance(cents: Int)
}

/// The account close and reopen rules (§4.7).
///
/// Accounts are never hard-deleted. Closing is blocked until the balance is zero,
/// so no exclusion rule is needed for Available Cash or Net Worth afterwards.
public enum AccountLifecycle {

    /// Reports what is stopping an account from being closed.
    /// - Parameter account: The account being closed.
    /// - Returns: The blocker, or `nil` when the balance is zero and closing may proceed.
    public static func blocker(for account: Account) -> CloseBlocker? {
        let balance = account.cachedBalanceCents
        guard balance != 0 else { return nil }
        return balance > 0 ? .holdsBalance(cents: balance) : .owesBalance(cents: -balance)
    }

    /// Returns the account marked closed as of a date.
    /// - Parameters:
    ///   - account: The account to close.
    ///   - date: When it was closed.
    /// - Returns: The closed account.
    public static func closed(_ account: Account, on date: Date = .now) -> Account {
        var closed = account
        closed.isClosed = true
        closed.closedDate = date
        return closed
    }

    /// Returns the account with its closed state cleared, restoring editability.
    /// - Parameter account: The account to reopen.
    /// - Returns: The reopened account.
    public static func reopened(_ account: Account) -> Account {
        var reopened = account
        reopened.isClosed = false
        reopened.closedDate = nil
        return reopened
    }

    /// Builds the transfer that zeroes an account so it can be closed.
    ///
    /// Direction follows the sign: a positive balance moves out of the account, and
    /// a negative one — a card that owes money — is paid off from the other account.
    ///
    /// - Parameters:
    ///   - account: The account being zeroed.
    ///   - counterpartID: The other account taking or supplying the money.
    ///   - date: The date both legs carry.
    /// - Returns: The two transfer legs.
    /// - Throws: ``TransferError`` when the balance is zero or the counterpart is the
    ///   account itself.
    public static func zeroingTransfer(
        for account: Account,
        counterpartID: UUID,
        date: Date = .now
    ) throws -> (out: Transaction, in: Transaction) {
        let balance = account.cachedBalanceCents
        let source = balance > 0 ? account.id : counterpartID
        let destination = balance > 0 ? counterpartID : account.id
        return try TransferFactory.makeLegs(
            amountCents: abs(balance),
            date: date,
            sourceAccountID: source,
            destinationAccountID: destination,
            merchant: balance > 0 ? "Closing \(account.name)" : "Paying off \(account.name)"
        )
    }
}
