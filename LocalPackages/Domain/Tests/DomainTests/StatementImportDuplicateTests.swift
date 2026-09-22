import Foundation
import Testing
@testable import Domain

/// How many copies of a purchase an import writes, and how far apart two readings of one
/// purchase may sit before they stop being the same purchase (§4.2).
///
/// Split from ``StatementImportPlannerTests`` to keep each file within the 300-line limit.
@Suite("Statement import duplicates")
struct StatementImportDuplicateTests {

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
    ///   - date: The row's date.
    /// - Returns: The document.
    private func statement(
        descriptor: String,
        cents: Int,
        date: Date = Fixtures.day(-3)
    ) -> StatementDocument {
        StatementDocument(
            rows: [StatementRow(date: date, rawDescriptor: descriptor, amountCents: cents)]
        )
    }

    @Test("The same charge printed twice in one statement is imported twice")
    func repeatsWithinOneStatementAreBothKept() {
        // A bank printing a line twice is reporting two purchases, not making a mistake:
        // two coffees at one shop for one price on one day is an ordinary morning.
        let document = StatementDocument(rows: [
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "BLUE BOTTLE", amountCents: 675),
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "BLUE BOTTLE", amountCents: 675)
        ])

        let plan = StatementImportPlanner.plan(document, in: context())

        #expect(plan.additions.count == 2)
        #expect(plan.skipped.isEmpty)
    }

    @Test("A statement listing a charge twice against one recorded entry writes only the second")
    func occurrenceCountDecidesHowManyAreWritten() {
        // The occurrence rule: the statement says two, the ledger holds one, so one is owed.
        let recorded = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3), merchant: "Blue Bottle"
        )
        let document = StatementDocument(rows: [
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "Blue Bottle", amountCents: 675),
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "Blue Bottle", amountCents: 675)
        ])

        let plan = StatementImportPlanner.plan(document, in: context(existing: [recorded]))

        #expect(plan.additions.count == 1)
        #expect(plan.skipped.map(\.reason) == [.exactDuplicate])
    }

    @Test("A charge posted three days late is not added again")
    func weekendPostingLagIsAbsorbed() {
        // A Friday purchase posts on the Monday. The merchant agrees, so this is the same
        // purchase and needs nobody's attention.
        let typed = Fixtures.transaction(
            .expense, cents: 4_120, account: card, date: Fixtures.day(-6), merchant: "Amazon"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "Amazon", cents: 4_120, date: Fixtures.day(-3)),
            in: context(existing: [typed])
        )

        #expect(plan.additions.isEmpty)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.exactDuplicate])
    }

    @Test("A charge four days apart is outside the window and is imported")
    func beyondTheWindowIsANewCharge() {
        let typed = Fixtures.transaction(
            .expense, cents: 4_120, account: card, date: Fixtures.day(-7), merchant: "Amazon"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "Amazon", cents: 4_120, date: Fixtures.day(-3)),
            in: context(existing: [typed])
        )

        #expect(plan.additions.count == 1)
        #expect(plan.conflicts.isEmpty)
    }

    @Test("A different wording several days apart is reported as a nearby-day conflict")
    func nearbyDayConflictCarriesItsOwnReason() {
        let mine = Fixtures.transaction(
            .expense, cents: 4_120, account: card, date: Fixtures.day(-6), merchant: "Amazon"
        )

        let plan = StatementImportPlanner.plan(
            statement(descriptor: "AMZN Mktp US*2K4TQ", cents: 4_120, date: Fixtures.day(-3)),
            in: context(existing: [mine])
        )

        #expect(plan.conflicts.first?.reason == .nearbyDaySameAmount)
    }

    @Test("Two incoming rows do not both conflict against one recorded entry")
    func oneExistingEntryAnswersOnlyOneRow() {
        // Consumption is what stops the user being asked the same question twice and then
        // losing a real purchase to whichever answer they gave second.
        let mine = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3), merchant: "Blue Bottle"
        )
        let document = StatementDocument(rows: [
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "SQ *BLUE BOTTLE 1042",
                         amountCents: 675),
            StatementRow(date: Fixtures.day(-3), rawDescriptor: "SQ *BLUE BOTTLE 1042",
                         amountCents: 675)
        ])

        let plan = StatementImportPlanner.plan(document, in: context(existing: [mine]))

        #expect(plan.conflicts.count == 1)
        #expect(plan.additions.count == 1)
    }
}
