import Foundation
import Testing
@testable import Domain

/// Phase 2 acceptance criteria for the exclusions that keep totals honest
/// (§4.3, §4.4, §7.4).
@Suite("Spend and income totals")
struct TotalsEngineTests {

    @Test("Expenses and income total independently")
    func plainTotals() {
        let account = Fixtures.account()
        let transactions = [
            Fixtures.transaction(.expense, cents: 2_500, account: account),
            Fixtures.transaction(.expense, cents: 1_500, account: account),
            Fixtures.transaction(.income, cents: 10_000, account: account)
        ]

        #expect(TotalsEngine.spendTotalCents(transactions: transactions, asOf: Fixtures.now) == 4_000)
        #expect(TotalsEngine.incomeTotalCents(transactions: transactions, asOf: Fixtures.now) == 10_000)
        #expect(TotalsEngine.netTotalCents(transactions: transactions, asOf: Fixtures.now) == 6_000)
    }

    @Test("Both transfer legs are absent from spend, income and net")
    func transfersAreExcluded() throws {
        let source = Fixtures.account(name: "Chequing")
        let card = Fixtures.account(name: "TD Visa", kind: .card)
        let purchase = Fixtures.transaction(.expense, cents: 6_000, account: card)
        let payment = try TransferFactory.makeLegs(
            amountCents: 6_000,
            date: Fixtures.day(-1),
            sourceAccountID: source.id,
            destinationAccountID: card.id
        )
        let transactions = [purchase, payment.out, payment.in]

        let spend = TotalsEngine.spendTotalCents(transactions: transactions, asOf: Fixtures.now)
        let income = TotalsEngine.incomeTotalCents(transactions: transactions, asOf: Fixtures.now)

        #expect(spend == 6_000, "The card payment must not double-count the purchase")
        #expect(income == 0, "A transfer inflow is not income")
    }

    @Test("An adjustment appears in neither spend nor income")
    func adjustmentsAreExcluded() {
        let account = Fixtures.account()
        let spendEntry = Fixtures.transaction(.expense, cents: 3_000, account: account)
        let negative = AdjustmentFactory.make(
            accountID: account.id, signedCents: -2_000, date: Fixtures.day(-1)
        )
        let positive = AdjustmentFactory.make(
            accountID: account.id, signedCents: 2_000, date: Fixtures.day(-1)
        )
        let transactions = [spendEntry, negative, positive]

        #expect(TotalsEngine.spendTotalCents(transactions: transactions, asOf: Fixtures.now) == 3_000)
        #expect(TotalsEngine.incomeTotalCents(transactions: transactions, asOf: Fixtures.now) == 0)
    }

    @Test("Unposted transactions are excluded from totals")
    func unpostedAreExcluded() {
        let account = Fixtures.account()
        let posted = Fixtures.transaction(.expense, cents: 1_000, account: account)
        let future = Fixtures.transaction(
            .expense, cents: 9_000, account: account, date: Fixtures.day(10)
        )

        let total = TotalsEngine.spendTotalCents(
            transactions: [posted, future], asOf: Fixtures.now
        )

        #expect(total == 1_000)
    }

    @Test("A date range restricts the total")
    func rangeRestrictsTotal() {
        let account = Fixtures.account()
        let inRange = Fixtures.transaction(
            .expense, cents: 1_000, account: account, date: Fixtures.day(-5)
        )
        let outOfRange = Fixtures.transaction(
            .expense, cents: 8_000, account: account, date: Fixtures.day(-40)
        )
        let range = Fixtures.day(-10)...Fixtures.now

        let total = TotalsEngine.spendTotalCents(
            transactions: [inRange, outOfRange], in: range, asOf: Fixtures.now
        )

        #expect(total == 1_000)
    }

    @Test("Only expenses and income count toward totals")
    func eligibilityByType() {
        let account = Fixtures.account()
        let cases: [(TransactionType, Bool)] = [
            (.expense, true), (.income, true),
            (.transferIn, false), (.transferOut, false), (.adjustment, false)
        ]

        for (type, expected) in cases {
            let transaction = Fixtures.transaction(type, cents: 100, account: account)
            #expect(
                TotalsEngine.countsTowardTotals(transaction, asOf: Fixtures.now) == expected,
                "\(type) eligibility"
            )
        }
    }
}
