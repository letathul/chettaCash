import Foundation
import Testing
@testable import Domain

/// Phase 2 acceptance criteria for balance derivation (§4.1, §4.2, §7.9).
@Suite("Balance derivation")
struct BalanceEngineTests {

    @Test("An expense reduces the account balance")
    func expenseReducesBalance() {
        let account = Fixtures.account(openingCents: 10_000)
        let expense = Fixtures.transaction(.expense, cents: 2_500, account: account)

        let balance = BalanceEngine.currentBalanceCents(
            account: account, transactions: [expense], asOf: Fixtures.now
        )

        #expect(balance == 7_500)
    }

    @Test("Income increases the account balance")
    func incomeIncreasesBalance() {
        let account = Fixtures.account(openingCents: 10_000)
        let income = Fixtures.transaction(.income, cents: 4_000, account: account)

        let balance = BalanceEngine.currentBalanceCents(
            account: account, transactions: [income], asOf: Fixtures.now
        )

        #expect(balance == 14_000)
    }

    @Test("An expense on a card makes the balance more negative")
    func cardExpenseIncreasesDebt() {
        let card = Fixtures.account(name: "TD Visa", kind: .card, openingCents: -5_000)
        let charge = Fixtures.transaction(.expense, cents: 3_000, account: card)

        let balance = BalanceEngine.currentBalanceCents(
            account: card, transactions: [charge], asOf: Fixtures.now
        )

        #expect(balance == -8_000)
        #expect(balance < card.openingBalanceCents)
    }

    @Test("A card payment moves the balance toward zero without special-casing sign")
    func cardPaymentMovesTowardZero() {
        let card = Fixtures.account(name: "TD Visa", kind: .card, openingCents: -10_000)
        let payment = Fixtures.transaction(.transferIn, cents: 4_000, account: card)

        let balance = BalanceEngine.currentBalanceCents(
            account: card, transactions: [payment], asOf: Fixtures.now
        )

        #expect(balance == -6_000)
    }

    @Test("A future-dated transaction does not affect the balance until its date")
    func futureTransactionIsInert() {
        let account = Fixtures.account(openingCents: 10_000)
        let future = Fixtures.transaction(
            .expense, cents: 2_000, account: account, date: Fixtures.day(5)
        )

        let before = BalanceEngine.currentBalanceCents(
            account: account, transactions: [future], asOf: Fixtures.now
        )
        let after = BalanceEngine.currentBalanceCents(
            account: account, transactions: [future], asOf: Fixtures.day(6)
        )

        #expect(before == 10_000)
        #expect(after == 8_000)
        #expect(BalanceEngine.isPosted(future, asOf: Fixtures.now) == false)
    }

    @Test("An adjustment corrects the balance using its signed override")
    func adjustmentCorrectsBalance() {
        let account = Fixtures.account(openingCents: 10_000)
        let correction = AdjustmentFactory.make(
            accountID: account.id, signedCents: -1_250, date: Fixtures.day(-1)
        )

        let balance = BalanceEngine.currentBalanceCents(
            account: account, transactions: [correction], asOf: Fixtures.now
        )

        #expect(balance == 8_750)
    }

    @Test("Transactions belonging to other accounts are ignored")
    func otherAccountsAreIgnored() {
        let account = Fixtures.account(openingCents: 10_000)
        let other = Fixtures.account(name: "Savings", openingCents: 500)
        let foreign = Fixtures.transaction(.expense, cents: 9_000, account: other)

        let balance = BalanceEngine.currentBalanceCents(
            account: account, transactions: [foreign], asOf: Fixtures.now
        )

        #expect(balance == 10_000)
    }

    @Test("A card's opening balance is stored negative regardless of typed sign")
    func cardOpeningBalanceIsNormalized() {
        #expect(BalanceEngine.normalizedOpeningBalanceCents(5_000, kind: .card) == -5_000)
        #expect(BalanceEngine.normalizedOpeningBalanceCents(-5_000, kind: .card) == -5_000)
        #expect(BalanceEngine.normalizedOpeningBalanceCents(5_000, kind: .account) == 5_000)
        #expect(BalanceEngine.normalizedOpeningBalanceCents(-5_000, kind: .account) == -5_000)
    }
}

/// Phase 2 acceptance criteria for the two headline figures (§4.1).
@Suite("Available Cash and Net Worth")
struct NetWorthTests {

    @Test("Available Cash excludes cards while Net Worth includes them")
    func cardsCountTowardNetWorthOnly() {
        let chequing = Fixtures.account(name: "Chequing", openingCents: 100_000)
        let savings = Fixtures.account(name: "Savings", openingCents: 50_000)
        let card = Fixtures.account(name: "TD Visa", kind: .card, openingCents: -20_000)
        let accounts = [chequing, savings, card]

        let cash = BalanceEngine.availableCashCents(
            accounts: accounts, transactions: [], asOf: Fixtures.now
        )
        let netWorth = BalanceEngine.netWorthCents(
            accounts: accounts, transactions: [], asOf: Fixtures.now
        )

        #expect(cash == 150_000)
        #expect(netWorth == 130_000)
    }

    @Test("Closed accounts are excluded from both figures")
    func closedAccountsAreExcluded() {
        let open = Fixtures.account(name: "Chequing", openingCents: 100_000)
        let closed = Fixtures.account(name: "Old", openingCents: 7_000, isClosed: true)
        let closedCard = Fixtures.account(
            name: "Old Visa", kind: .card, openingCents: -3_000, isClosed: true
        )
        let accounts = [open, closed, closedCard]

        let cash = BalanceEngine.availableCashCents(
            accounts: accounts, transactions: [], asOf: Fixtures.now
        )
        let netWorth = BalanceEngine.netWorthCents(
            accounts: accounts, transactions: [], asOf: Fixtures.now
        )

        #expect(cash == 100_000)
        #expect(netWorth == 100_000)
    }
}
