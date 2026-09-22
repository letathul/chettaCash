import Foundation
import Testing
@testable import Domain

/// Phase 4 acceptance criteria for the account close flow (§4.7).
@Suite("Account lifecycle")
struct AccountLifecycleTests {

    /// Builds an account carrying a given derived balance.
    /// - Parameters:
    ///   - cents: The cached balance.
    ///   - kind: Spending account or card.
    /// - Returns: The account.
    private func account(balance cents: Int, kind: AccountKind = .account) -> Account {
        Account(name: "Test", kind: kind, cachedBalanceCents: cents)
    }

    @Test("Closing is blocked while a cash account still holds money")
    func blockedWhenHoldingBalance() {
        #expect(AccountLifecycle.blocker(for: account(balance: 12_500)) == .holdsBalance(cents: 12_500))
    }

    @Test("Closing is blocked while a card still owes money")
    func blockedWhenOwing() {
        let card = account(balance: -8_000, kind: .card)
        #expect(AccountLifecycle.blocker(for: card) == .owesBalance(cents: 8_000))
    }

    @Test("Closing is allowed once the balance is zero")
    func allowedAtZero() {
        #expect(AccountLifecycle.blocker(for: account(balance: 0)) == nil)
    }

    @Test("Closing stamps the flag and the date")
    func closingStampsDate() {
        let when = Date(timeIntervalSince1970: 1_789_000_000)
        let closed = AccountLifecycle.closed(account(balance: 0), on: when)
        #expect(closed.isClosed)
        #expect(closed.closedDate == when)
    }

    @Test("Reopening clears both fields and restores editability")
    func reopeningClearsState() {
        let closed = AccountLifecycle.closed(account(balance: 0))
        let reopened = AccountLifecycle.reopened(closed)
        #expect(reopened.isClosed == false)
        #expect(reopened.closedDate == nil)
    }

    @Test("A positive balance transfers out of the account being closed")
    func zeroingMovesMoneyOut() throws {
        let closing = account(balance: 25_000)
        let destination = Account(name: "Savings")

        let legs = try AccountLifecycle.zeroingTransfer(
            for: closing, counterpartID: destination.id
        )

        #expect(legs.out.accountID == closing.id)
        #expect(legs.in.accountID == destination.id)
        #expect(legs.out.amountCents == 25_000)
    }

    @Test("A card that owes money is paid off from the other account")
    func zeroingPaysOffCard() throws {
        let card = account(balance: -8_000, kind: .card)
        let chequing = Account(name: "Chequing")

        let legs = try AccountLifecycle.zeroingTransfer(for: card, counterpartID: chequing.id)

        #expect(legs.out.accountID == chequing.id)
        #expect(legs.in.accountID == card.id)
        #expect(legs.in.amountCents == 8_000)
    }

    @Test("The zeroing transfer leaves the closing account at zero")
    func zeroingActuallyZeroes() throws {
        var closing = account(balance: 25_000)
        closing.openingBalanceCents = 25_000
        let destination = Account(name: "Savings")
        let legs = try AccountLifecycle.zeroingTransfer(
            for: closing, counterpartID: destination.id, date: .distantPast
        )

        let balance = BalanceEngine.currentBalanceCents(
            account: closing, transactions: [legs.out, legs.in]
        )

        #expect(balance == 0)
    }

    @Test("A zero-balance account has no transfer to offer")
    func zeroBalanceHasNoTransfer() {
        let settled = account(balance: 0)
        #expect(throws: TransferError.nonPositiveAmount) {
            try AccountLifecycle.zeroingTransfer(for: settled, counterpartID: UUID())
        }
    }
}
