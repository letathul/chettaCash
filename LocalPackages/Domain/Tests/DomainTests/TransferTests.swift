import Foundation
import Testing
@testable import Domain

/// Phase 2 acceptance criteria for transfers (§4.3).
@Suite("Transfers")
struct TransferTests {

    @Test("A transfer moves money between accounts")
    func transferMovesMoney() throws {
        let source = Fixtures.account(name: "Chequing", openingCents: 100_000)
        let destination = Fixtures.account(name: "Savings", openingCents: 0)
        let legs = try TransferFactory.makeLegs(
            amountCents: 25_000,
            date: Fixtures.day(-1),
            sourceAccountID: source.id,
            destinationAccountID: destination.id
        )
        let all = [legs.out, legs.in]

        let sourceBalance = BalanceEngine.currentBalanceCents(
            account: source, transactions: all, asOf: Fixtures.now
        )
        let destinationBalance = BalanceEngine.currentBalanceCents(
            account: destination, transactions: all, asOf: Fixtures.now
        )

        #expect(sourceBalance == 75_000)
        #expect(destinationBalance == 25_000)
    }

    @Test("Both legs share a group ID, amount and date, and carry no category")
    func legsAreConsistent() throws {
        let source = Fixtures.account()
        let destination = Fixtures.account(name: "Savings")
        let date = Fixtures.day(-3)

        let legs = try TransferFactory.makeLegs(
            amountCents: 12_345,
            date: date,
            sourceAccountID: source.id,
            destinationAccountID: destination.id
        )

        #expect(legs.out.transferGroupID == legs.in.transferGroupID)
        #expect(legs.out.transferGroupID != nil)
        #expect(legs.out.amountCents == legs.in.amountCents)
        #expect(legs.out.date == legs.in.date)
        #expect(legs.out.date == date)
        #expect(legs.out.categoryID == nil)
        #expect(legs.in.categoryID == nil)
        #expect(legs.out.type == .transferOut)
        #expect(legs.in.type == .transferIn)
        #expect(legs.out.accountID == source.id)
        #expect(legs.in.accountID == destination.id)
    }

    @Test("A transfer to the same account is rejected")
    func sameAccountIsRejected() {
        let account = Fixtures.account()

        #expect(throws: TransferError.sameAccount) {
            try TransferFactory.makeLegs(
                amountCents: 1_000,
                date: Fixtures.now,
                sourceAccountID: account.id,
                destinationAccountID: account.id
            )
        }
    }

    @Test("A non-positive transfer amount is rejected", arguments: [0, -1, -5_000])
    func nonPositiveAmountIsRejected(cents: Int) {
        let source = Fixtures.account()
        let destination = Fixtures.account(name: "Savings")

        #expect(throws: TransferError.nonPositiveAmount) {
            try TransferFactory.makeLegs(
                amountCents: cents,
                date: Fixtures.now,
                sourceAccountID: source.id,
                destinationAccountID: destination.id
            )
        }
    }

    @Test("Deleting one leg deletes both")
    func deletingOneLegDeletesBoth() async throws {
        let source = Fixtures.account(name: "Chequing")
        let destination = Fixtures.account(name: "Savings")
        let legs = try TransferFactory.makeLegs(
            amountCents: 5_000,
            date: Fixtures.day(-1),
            sourceAccountID: source.id,
            destinationAccountID: destination.id
        )
        let repository = InMemoryTransactionRepository()
        try await repository.saveTransfer(outLeg: legs.out, inLeg: legs.in)
        #expect(try await repository.transactions(accountID: nil, in: nil).count == 2)

        try await repository.delete(id: legs.out.id)

        let remaining = try await repository.transactions(accountID: nil, in: nil)
        #expect(remaining.isEmpty, "A half-transfer must never exist in the database")
    }

    @Test("Deleting the inflow leg also removes the outflow leg")
    func deletingInflowLegDeletesBoth() async throws {
        let source = Fixtures.account(name: "Chequing")
        let destination = Fixtures.account(name: "Savings")
        let legs = try TransferFactory.makeLegs(
            amountCents: 5_000,
            date: Fixtures.day(-1),
            sourceAccountID: source.id,
            destinationAccountID: destination.id
        )
        let repository = InMemoryTransactionRepository()
        try await repository.saveTransfer(outLeg: legs.out, inLeg: legs.in)

        try await repository.delete(id: legs.in.id)

        let remaining = try await repository.transactions(accountID: nil, in: nil)
        #expect(remaining.isEmpty)
    }

    @Test("Deleting a plain transaction leaves others untouched")
    func deletingPlainTransactionIsScoped() async throws {
        let account = Fixtures.account()
        let first = Fixtures.transaction(.expense, cents: 100, account: account)
        let second = Fixtures.transaction(.expense, cents: 200, account: account)
        let repository = InMemoryTransactionRepository()
        try await repository.save(first)
        try await repository.save(second)

        try await repository.delete(id: first.id)

        let remaining = try await repository.transactions(accountID: nil, in: nil)
        #expect(remaining.map(\.id) == [second.id])
    }
}
