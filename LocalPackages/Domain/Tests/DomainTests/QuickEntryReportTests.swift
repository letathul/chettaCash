import Foundation
import Testing
@testable import Domain

/// What a Shortcut run has to say for itself (§15.7).
///
/// A background intent has no screen, so anything it decided that the user did not say has
/// to be spoken or it never happened as far as they know. These pin down what gets
/// mentioned and in what order; the App layer only turns each clause into words.
@Suite("Quick entry report")
struct QuickEntryReportTests {

    @Test("A plain run says only that it logged the entry")
    func plainRunSaysOneThing() {
        let clauses = QuickEntryReporter.clauses(for: QuickEntryReport())

        #expect(clauses == [.logged])
    }

    @Test("A created account is always named back")
    func namesACreatedAccount() {
        let report = QuickEntryReport(createdAccountName: "Card ••9087")

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(
            clauses == [.logged, .createdAccount("Card ••9087")],
            "a card appearing unannounced in the accounts list reads as a bug"
        )
    }

    @Test("A parked entry says why, so the Today card is not a surprise")
    func explainsAParkedEntry() {
        let report = QuickEntryReport(parkedReason: .ambiguousNumber(count: 2))

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(clauses == [.logged, .parked(.ambiguousNumber(count: 2))])
    }

    @Test("An entry cannot both have an account made for it and have none")
    func parkingBeatsCreation() {
        let report = QuickEntryReport(
            createdAccountName: "Apple Card", parkedReason: .unrecognisedName
        )

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(clauses == [.logged, .parked(.unrecognisedName)])
    }

    @Test("A future-dated entry says it has not moved the balance yet")
    func flagsAFutureEntry() {
        let report = QuickEntryReport(isPosted: false)

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(clauses == [.logged, .notYetPosted])
    }

    @Test("A pin created on the way past is said out loud once")
    func announcesANewPin() {
        let report = QuickEntryReport(pinnedCategoryLabel: "Groceries")

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(
            clauses == [.logged, .pinned("Groceries")],
            "the pin outranks whatever every later run of this Shortcut passes"
        )
    }

    @Test("Everything at once is said in one order")
    func ordersEveryClause() {
        let report = QuickEntryReport(
            createdAccountName: "Card ••9087",
            isPosted: false,
            pinnedCategoryLabel: "Groceries"
        )

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(
            clauses == [
                .logged, .createdAccount("Card ••9087"), .notYetPosted, .pinned("Groceries")
            ]
        )
    }

    @Test("A repeat says that and nothing else")
    func aRepeatSaysNothingFurther() {
        let report = QuickEntryReport(
            wasAlreadyLogged: true,
            createdAccountName: "Card ••9087",
            isPosted: false,
            pinnedCategoryLabel: "Groceries"
        )

        let clauses = QuickEntryReporter.clauses(for: report)

        #expect(
            clauses == [.alreadyLogged],
            "the account, the pin and the date were all settled the first time"
        )
    }
}
