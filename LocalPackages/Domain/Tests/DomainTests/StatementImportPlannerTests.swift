import Foundation
import Testing
@testable import Domain

/// Sorting a statement's rows into what to write, what to ask about, and what to drop (§4.2).
@Suite("Statement import planning")
struct StatementImportPlannerTests {

    /// The card every statement in this suite belongs to.
    private let card = Fixtures.account(name: "Visa", kind: .card)

    /// Builds a context against this suite's card.
    /// - Parameters:
    ///   - existing: Transactions already recorded.
    ///   - tolerance: Days either side that still count as the same purchase.
    /// - Returns: The context.
    private func context(
        existing: [Transaction] = [],
        tolerance: Int = 3
    ) -> StatementImportContext {
        StatementImportContext(
            accountID: card.id,
            existing: existing,
            calendar: Fixtures.utc,
            dayTolerance: tolerance
        )
    }

    /// Builds a one-row statement.
    /// - Parameters:
    ///   - descriptor: The descriptor as printed.
    ///   - cents: Positive magnitude in cents.
    ///   - date: The posting date.
    ///   - kind: Charge, refund or payment.
    /// - Returns: The document.
    private func statement(
        descriptor: String,
        cents: Int,
        date: Date = Fixtures.day(-3),
        kind: StatementRowKind = .charge
    ) -> StatementDocument {
        StatementDocument(
            rows: [StatementRow(date: date, rawDescriptor: descriptor,
                                amountCents: cents, kind: kind)]
        )
    }

    @Test("A row the ledger does not have becomes a new transaction")
    func newRowIsAdded() {
        let plan = StatementImportPlanner.plan(
            statement(descriptor: "BLUE BOTTLE", cents: 675), in: context()
        )

        #expect(plan.additions.count == 1)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.additions.first?.amountCents == 675)
        #expect(plan.additions.first?.type == .expense)
    }

    @Test("Importing the same statement twice adds nothing the second time")
    func importIsIdempotent() {
        // The headline guarantee, and the reason the fingerprint exists at all.
        let document = statement(descriptor: "BLUE BOTTLE", cents: 675)
        let first = StatementImportPlanner.plan(document, in: context())

        let second = StatementImportPlanner.plan(
            document, in: context(existing: first.additions)
        )

        #expect(second.additions.isEmpty)
        #expect(second.conflicts.isEmpty)
        #expect(second.skipped.map(\.reason) == [.exactDuplicate])
    }

    @Test("A different wording at the same amount and day raises a conflict, not a silent skip")
    func differentWordingBecomesAConflict() {
        let mine = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3), merchant: "Blue Bottle"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "SQ *BLUE BOTTLE COFFEE 1042", cents: 675),
            in: context(existing: [mine])
        )

        #expect(plan.additions.isEmpty)
        #expect(plan.conflicts.count == 1)
        #expect(plan.conflicts.first?.reason == .sameDaySameAmount)
        #expect(plan.conflicts.first?.existing.id == mine.id)
    }

    @Test("A charge posted a day late still matches what the user typed")
    func postingLagIsTolerated() {
        // A statement prints the posting date, routinely a day after the purchase.
        let typed = Fixtures.transaction(
            .expense, cents: 4_120, account: card, date: Fixtures.day(-4), merchant: "Amazon"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "AMZN Mktp US*2K4TQ", cents: 4_120, date: Fixtures.day(-3)),
            in: context(existing: [typed])
        )

        #expect(plan.conflicts.count == 1)
        #expect(plan.conflicts.first?.reason == .adjacentDaySameAmount)
    }

    @Test("With no day tolerance a late posting is treated as a new charge")
    func toleranceCanBeTurnedOff() {
        let typed = Fixtures.transaction(
            .expense, cents: 4_120, account: card, date: Fixtures.day(-4), merchant: "Amazon"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "AMZN Mktp US*2K4TQ", cents: 4_120, date: Fixtures.day(-3)),
            in: context(existing: [typed], tolerance: 0)
        )

        #expect(plan.conflicts.isEmpty)
        #expect(plan.additions.count == 1)
    }

    @Test("A refund of the same amount is never mistaken for the charge")
    func oppositeSignIsNeverADuplicate() {
        let charge = Fixtures.transaction(
            .expense, cents: 5_000, account: card, date: Fixtures.day(-3), merchant: "Acme"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "ACME REFUND", cents: 5_000, kind: .refund),
            in: context(existing: [charge])
        )

        #expect(plan.conflicts.isEmpty)
        #expect(plan.additions.first?.type == .income)
    }

    @Test("A card payment is left out rather than imported as income or a half-transfer")
    func cardPaymentsAreSkipped() {
        let plan = StatementImportPlanner.plan(
            statement(descriptor: "PAYMENT - THANK YOU", cents: 50_000, kind: .payment),
            in: context()
        )

        #expect(plan.additions.isEmpty)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.cardPayment])
    }

    @Test("A row with no readable amount is left out rather than imported as zero")
    func unreadableAmountsAreSkipped() {
        let plan = StatementImportPlanner.plan(
            statement(descriptor: "SOMETHING", cents: 0), in: context()
        )

        #expect(plan.additions.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.unreadableAmount])
    }

    @Test("Every imported row carries the statement tag so the import can be found later")
    func importedRowsAreTagged() {
        let plan = StatementImportPlanner.plan(
            statement(descriptor: "BLUE BOTTLE", cents: 675), in: context()
        )

        #expect(plan.additions.first?.tags == [StatementImportPlanner.originTag])
    }

    @Test("A tidied merchant name keeps the statement's own wording in the memo")
    func rawDescriptorSurvivesCleanup() {
        let row = StatementRow(
            date: Fixtures.day(-3), rawDescriptor: "SQ *BLUE BOTTLE 1042",
            amountCents: 675, cleanedMerchant: "Blue Bottle"
        )

        let plan = StatementImportPlanner.plan(
            StatementDocument(rows: [row]), in: context()
        )
        let added = plan.additions.first

        #expect(added?.merchant == "Blue Bottle")
        #expect(added?.memo == "Statement: SQ *BLUE BOTTLE 1042")
    }

    @Test("A merchant pin decides the category")
    func pinResolvesCategory() throws {
        let groceries = Category(label: "Groceries", context: .expense)
        // Pinned on a spelling that normalises the same as the statement's descriptor:
        // `MerchantCategoryIndex` drops the trailing branch number but keeps "mkt".
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Whole Foods Mkt", categoryID: groceries.id)
        )
        var withPin = context()
        withPin.pins = [pin]
        withPin.selectableCategories = [groceries]

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "WHOLE FOODS MKT #10234", cents: 8_432), in: withPin
        )

        #expect(plan.additions.first?.categoryID == groceries.id)
    }

    @Test("The row count is reported whatever happened to the rows")
    func everyRowIsCounted() {
        let document = StatementDocument(rows: [
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "A", amountCents: 100),
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "PAYMENT - THANK YOU",
                         amountCents: 500, kind: .payment),
            StatementRow(date: Fixtures.day(-2), rawDescriptor: "B", amountCents: 0)
        ])

        let plan = StatementImportPlanner.plan(document, in: context())

        #expect(plan.rowsProcessed == 3)
        #expect(plan.additions.count == 1)
        #expect(plan.skipped.count == 2)
    }
}
