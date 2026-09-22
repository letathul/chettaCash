import Foundation
import Testing
@testable import Domain

/// Finding the card a statement belongs to, and when one may be created (§9.7).
@Suite("Matching a statement to its card")
struct StatementAccountProvisionerTests {

    /// Builds a card with digits and a network.
    /// - Parameters:
    ///   - name: Display name.
    ///   - last4: The card's last four digits.
    ///   - network: The network it runs on.
    ///   - isClosed: Whether the account is closed.
    /// - Returns: The card.
    private func card(
        name: String,
        last4: String?,
        network: CardNetwork?,
        isClosed: Bool = false
    ) -> Account {
        var account = Fixtures.account(name: name, kind: .card, isClosed: isClosed)
        account.last4 = last4
        account.cardNetwork = network
        return account
    }

    @Test("One matching card is used")
    func singleMatchIsUsed() {
        let visa = card(name: "Visa", last4: "4417", network: .visa)

        let match = StatementAccountProvisioner.resolve(
            ReceiptTender(last4: "4417", network: .visa), in: [visa]
        )

        #expect(match == .matched(visa.id))
    }

    @Test("Two cards sharing the digits ask rather than create a third")
    func ambiguityNeverCreates() {
        // The important one. Creating here would add a card beside two the user has, and
        // every imported charge would land on the wrong balance.
        let first = card(name: "Visa personal", last4: "4417", network: .visa)
        let second = card(name: "Visa business", last4: "4417", network: .visa)

        let match = StatementAccountProvisioner.resolve(
            ReceiptTender(last4: "4417"), in: [first, second]
        )

        #expect(match == .ambiguous([first.id, second.id]))
    }

    @Test("Digits no account has produce a card to create")
    func unknownDigitsOfferACard() throws {
        let existing = card(name: "Amex", last4: "1009", network: .amex)

        let match = StatementAccountProvisioner.resolve(
            ReceiptTender(last4: "4417", network: .visa),
            in: [existing],
            openingDate: Fixtures.now
        )

        guard case .unknown(let proposed) = match else {
            Issue.record("Expected an unknown card, got \(match)")
            return
        }
        #expect(proposed.kind == .card)
        #expect(proposed.last4 == "4417")
        #expect(proposed.cardNetwork == .visa)
        #expect(proposed.name == "Visa ••4417")
        // Zero, so no phantom money appears: the imported charges alone derive the balance.
        #expect(proposed.openingBalanceCents == 0)
    }

    @Test("A card with no network still gets a usable name")
    func unknownDigitsWithoutNetwork() {
        let match = StatementAccountProvisioner.resolve(
            ReceiptTender(last4: "4417"), in: []
        )

        guard case .unknown(let proposed) = match else {
            Issue.record("Expected an unknown card, got \(match)")
            return
        }
        #expect(proposed.name == "Card ••4417")
        #expect(proposed.cardNetwork == nil)
    }

    @Test("A network with no digits creates nothing")
    func bareNetworkIsIndeterminate() {
        // "A Visa" does not say *which* Visa. A card invented from that would collect
        // charges belonging to one the user already has.
        let match = StatementAccountProvisioner.resolve(
            ReceiptTender(network: .visa), in: []
        )

        #expect(match == .indeterminate)
    }

    @Test("A statement that identifies no card at all creates nothing")
    func emptyTenderIsIndeterminate() {
        let match = StatementAccountProvisioner.resolve(ReceiptTender(), in: [])

        #expect(match == .indeterminate)
    }

    @Test("A closed card is never matched, and its digits are treated as unknown")
    func closedAccountsAreIgnored() {
        let closed = card(name: "Old Visa", last4: "4417", network: .visa, isClosed: true)

        let match = StatementAccountProvisioner.resolve(
            ReceiptTender(last4: "4417", network: .visa), in: [closed]
        )

        guard case .unknown = match else {
            Issue.record("Expected an unknown card, got \(match)")
            return
        }
    }
}

/// The summary an import reports when it finishes (§9.4).
@Suite("Import outcome summaries")
struct ImportOutcomeTests {

    @Test("A clean import names what it added")
    func addedRowsAreSummarised() {
        let outcome = ImportOutcome(rowsProcessed: 38, added: 31, exactDuplicatesSkipped: 5,
                                    conflictsRaised: 2)

        #expect(outcome.summary == "38 rows · 31 added · 5 already in your ledger · 2 to check")
    }

    @Test("Re-importing the same statement says nothing was new")
    func idempotentImportSaysSo() {
        let outcome = ImportOutcome(rowsProcessed: 38, added: 0, exactDuplicatesSkipped: 38)

        #expect(outcome.summary == "38 rows · 38 already in your ledger — nothing new")
        #expect(outcome.isNoOp)
    }

    @Test("Zero counts are left out rather than printed as zeroes")
    func zeroClausesAreOmitted() {
        let outcome = ImportOutcome(rowsProcessed: 4, added: 4)

        #expect(outcome.summary == "4 rows · 4 added")
    }

    @Test("An empty statement says there was nothing to import")
    func emptyStatement() {
        #expect(ImportOutcome().summary == "Nothing to import.")
    }

    @Test("Skipped card payments produce a note explaining what to do instead")
    func paymentNoteAppearsOnlyWhenNeeded() {
        #expect(ImportOutcome(rowsProcessed: 4, added: 4).paymentNote == nil)
        #expect(ImportOutcome(rowsProcessed: 5, added: 4, paymentsSkipped: 1).paymentNote != nil)
    }

    @Test("Resolving conflicts moves them out of the pending count")
    func pendingCountFollowsResolution() {
        let outcome = ImportOutcome(rowsProcessed: 10, added: 7, conflictsRaised: 3,
                                    conflictsResolved: 2)

        #expect(outcome.pendingConflicts == 1)
    }

    @Test("An outcome is built from the plan it applied")
    func outcomeCountsThePlan() {
        let card = Fixtures.account(name: "Visa", kind: .card)
        let plan = ImportPlan(
            additions: [Fixtures.transaction(.expense, cents: 100, account: card)],
            skipped: [
                SkippedRow(
                    row: StatementRow(date: Fixtures.now, rawDescriptor: "A", amountCents: 1),
                    reason: .exactDuplicate
                ),
                SkippedRow(
                    row: StatementRow(date: Fixtures.now, rawDescriptor: "PAYMENT",
                                      amountCents: 1, kind: .payment),
                    reason: .cardPayment
                )
            ],
            rowsProcessed: 3
        )

        let outcome = ImportOutcome.of(plan)

        #expect(outcome.rowsProcessed == 3)
        #expect(outcome.added == 1)
        #expect(outcome.exactDuplicatesSkipped == 1)
        #expect(outcome.paymentsSkipped == 1)
    }
}
