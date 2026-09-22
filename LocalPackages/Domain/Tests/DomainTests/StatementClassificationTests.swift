import Foundation
import Testing
@testable import Domain

/// Telling a charge from a refund from a card payment (§4.3).
@Suite("Classifying statement lines")
struct StatementRowClassifierTests {

    @Test("Payment wording on a credit marks it a payment")
    func paymentsAreRecognised() {
        let wordings = [
            "PAYMENT - THANK YOU", "AUTOPAY PYMT", "PRE-AUTHORIZED PAYMENT",
            "ONLINE BILL PAYMENT", "PAIEMENT MERCI"
        ]

        let kinds = wordings.map { StatementRowClassifier.kind(descriptor: $0, isCredit: true) }

        #expect(kinds.allSatisfy { $0 == .payment })
    }

    @Test("A credit with no payment wording is a refund")
    func creditsWithoutPaymentWordingAreRefunds() {
        let kind = StatementRowClassifier.kind(descriptor: "UNIQLO RETURN", isCredit: true)

        #expect(kind == .refund)
    }

    @Test("A shop whose name contains a payment word is still a charge")
    func debitsAreNeverPayments() {
        // "Payless" must not be read as a card payment, and the sign is what guarantees it:
        // a debit is a charge whatever it is called.
        let kind = StatementRowClassifier.kind(descriptor: "PAYLESS SHOESOURCE", isCredit: false)

        #expect(kind == .charge)
    }

    @Test("A word that merely contains a payment term does not count")
    func wholeWordsOnly() {
        // "Payless" contains "pay" but is not "payment"; matching on substrings would
        // silently drop a real refund from a shop with an unlucky name.
        #expect(!StatementRowClassifier.mentionsPayment("PAYLESS SHOESOURCE"))
        #expect(StatementRowClassifier.mentionsPayment("PAYMENT RECEIVED"))
    }
}

/// Judging duplicate pairs without a model (§9.7).
@Suite("Duplicate adjudication fallback")
struct HeuristicDuplicateAdjudicatorTests {

    /// The card the pairs in this suite are on.
    private let card = Fixtures.account(name: "Visa", kind: .card)

    /// Builds a conflict between two spellings.
    /// - Parameters:
    ///   - existing: What the ledger holds.
    ///   - incoming: What the statement says.
    /// - Returns: The conflict.
    private func conflict(existing: String, incoming: String) -> DuplicateConflict {
        DuplicateConflict(
            incoming: Fixtures.transaction(
                .expense, cents: 675, account: card, merchant: incoming
            ),
            row: StatementRow(
                date: Fixtures.day(-3), rawDescriptor: incoming, amountCents: 675
            ),
            existing: Fixtures.transaction(
                .expense, cents: 675, account: card, merchant: existing
            ),
            reason: .sameDaySameAmount
        )
    }

    @Test("Two spellings of one shop are called the same transaction")
    func overlappingNamesMatch() async {
        let pair = conflict(existing: "Blue Bottle", incoming: "SQ *BLUE BOTTLE COFFEE")

        let verdicts = await HeuristicDuplicateAdjudicator()
            .adjudicate([pair], context: DuplicateAdjudicationContext())

        #expect(verdicts.first?.judgement == .sameTransaction)
    }

    @Test("A shared leading shop name matches even when the rest differs")
    func leadingTokenMatches() async {
        let pair = conflict(existing: "Starbucks", incoming: "STARBUCKS STORE 00421 SEATTLE")

        let verdicts = await HeuristicDuplicateAdjudicator()
            .adjudicate([pair], context: DuplicateAdjudicationContext())

        #expect(verdicts.first?.judgement == .sameTransaction)
    }

    @Test("Unlike names are reported as unsure, never as different transactions")
    func unlikeNamesAreUnsure() async {
        // Plenty of real duplicates share no words — the user's "Headphones" against the
        // bank's "AMZN Mktp". Calling those different would hide a true duplicate.
        let pair = conflict(existing: "Headphones", incoming: "AMZN Mktp US*2K4TQ")

        let verdicts = await HeuristicDuplicateAdjudicator()
            .adjudicate([pair], context: DuplicateAdjudicationContext())

        #expect(verdicts.first?.judgement == .unsure)
        #expect(verdicts.first?.judgement != .differentTransactions)
    }

    @Test("Every conflict gets exactly one verdict, marked as the fallback's")
    func coversEveryConflictAndNamesItself() async {
        let pairs = [
            conflict(existing: "Blue Bottle", incoming: "BLUE BOTTLE"),
            conflict(existing: "Headphones", incoming: "AMZN")
        ]

        let verdicts = await HeuristicDuplicateAdjudicator()
            .adjudicate(pairs, context: DuplicateAdjudicationContext())

        #expect(verdicts.count == 2)
        #expect(verdicts.allSatisfy { $0.source == .textHeuristics })
        #expect(Set(verdicts.map(\.id)) == Set(pairs.map(\.id)))
    }

    @Test("Only an outright match pre-ticks a row for removal")
    func unsureNeverPreTicks() async {
        let pairs = [
            conflict(existing: "Blue Bottle", incoming: "BLUE BOTTLE"),
            conflict(existing: "Headphones", incoming: "AMZN")
        ]

        let verdicts = await HeuristicDuplicateAdjudicator()
            .adjudicate(pairs, context: DuplicateAdjudicationContext())

        #expect(verdicts.first?.suggestsRemovingIncoming == true)
        #expect(verdicts.last?.suggestsRemovingIncoming == false)
    }

    // MARK: - Merging two readers

    /// Builds a row on a fixed day.
    /// - Parameters:
    ///   - merchant: The descriptor as printed.
    ///   - cents: The amount in cents.
    ///   - day: Days from a fixed reference.
    /// - Returns: The row.
    private func row(_ merchant: String, cents: Int, day: Int = 0) -> StatementRow {
        StatementRow(
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400),
            rawDescriptor: merchant,
            amountCents: cents
        )
    }

    @Test("Two different shops charging the same amount on one day both survive the merge")
    func keepsSameDaySameAmountAtDifferentShops() {
        // The shape a real statement produced four times over: two purchases the old key
        // (day, amount, kind) could not tell apart, so one of each was silently discarded.
        let led = StatementDocument(rows: [row("MCDONALD'S #23799", cents: 654)])
        let backup = StatementDocument(rows: [
            row("MCDONALD'S #23799", cents: 654),
            row("COUCHE-TARD #1256", cents: 654)
        ])

        let merged = led.completed(with: backup)

        #expect(merged.rows.count == 2, "the second shop is a different purchase")
        #expect(merged.rows.contains { $0.merchant == "COUCHE-TARD #1256" })
    }

    @Test("The same shop twice on one day survives when both readers saw it twice")
    func keepsGenuineRepeatsAtOneShop() {
        // Indistinguishable from a double reading by content alone — two transit fares, two
        // coffees. What tells them apart is that each reader saw the line twice.
        let pair = [row("PRESTO AUTO", cents: 2_000), row("PRESTO AUTO", cents: 2_000)]

        let merged = StatementDocument(rows: pair).completed(with: StatementDocument(rows: pair))

        #expect(merged.rows.count == 2, "two fares are two fares")
    }

    @Test("Two readings of one line still collapse to a single row")
    func collapsesTwoReadingsOfOneLine() {
        let led = StatementDocument(rows: [
            StatementRow(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                rawDescriptor: "SQ *BLUE BOTTLE 1042",
                amountCents: 675,
                cleanedMerchant: "Blue Bottle"
            )
        ])
        let backup = StatementDocument(rows: [row("Blue Bottle", cents: 675)])

        #expect(led.completed(with: backup).rows.count == 1)
    }
}
