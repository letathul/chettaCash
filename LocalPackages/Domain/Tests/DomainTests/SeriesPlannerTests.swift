import Foundation
import Testing
@testable import Domain

/// Phase 6 acceptance criteria for the three edit and delete scopes (§4.5).
@Suite("Series edit and delete scopes")
struct SeriesPlannerTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC date at midday.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    /// - Returns: That instant.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    /// Builds a five-month series running from May to September.
    /// - Returns: The series.
    private func makeSeries() -> RecurringSeries {
        let rule = RecurringRule(
            name: "Gym",
            amountCents: 4_000,
            accountID: UUID(),
            frequency: .monthly,
            startDate: date(2026, 5, 1),
            occurrencesGenerated: 5
        )
        let occurrences = (0..<5).compactMap { index -> Transaction? in
            guard let when = RecurringSchedule.date(
                atIndex: index, of: rule, calendar: calendar
            ) else { return nil }
            return RecurringEngine.occurrence(of: rule, on: when)
        }
        return RecurringSeries(rule: rule, occurrences: occurrences)
    }

    /// The edited values the user typed.
    /// - Parameter target: The occurrence being edited.
    /// - Returns: The target carrying new values.
    private func edited(_ target: Transaction) -> Transaction {
        var edited = target
        edited.amountCents = 5_500
        edited.merchant = "Gym Plus"
        return edited
    }

    // MARK: - Edit scopes

    @Test("This occurrence only detaches the row and leaves the rule untouched")
    func editThisOccurrenceOnly() {
        let series = makeSeries()
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planEdit(
            series: series, target: target,
            scope: .thisOccurrence, edited: edited(target), calendar: calendar
        )

        #expect(plan.updatedTransactions.count == 1)
        #expect(plan.updatedTransactions.first?.isSeriesOverride == true)
        #expect(plan.updatedTransactions.first?.amountCents == 5_500)
        #expect(plan.updatedRules.isEmpty, "the rule keeps its own values")
        #expect(plan.deletedTransactionIDs.isEmpty)
    }

    @Test("This and future ends the old rule and starts a new one at that date")
    func editThisAndFuture() throws {
        let series = makeSeries()
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planEdit(
            series: series, target: target,
            scope: .thisAndFuture, edited: edited(target), calendar: calendar
        )

        #expect(plan.updatedRules.count == 2)
        let ended = try #require(plan.updatedRules.first { $0.id == series.rule.id })
        let successor = try #require(plan.updatedRules.first { $0.id != series.rule.id })

        #expect(ended.isActive == false)
        #expect(try #require(ended.endDate) < target.date)
        #expect(ended.occurrencesGenerated == 2, "May and June stay with the old rule")

        #expect(successor.startDate == target.date)
        #expect(successor.amountCents == 5_500)
        #expect(successor.name == "Gym Plus")
        #expect(successor.isActive)

        #expect(plan.updatedTransactions.count == 3, "July, August and September move across")
        #expect(plan.updatedTransactions.allSatisfy { $0.amountCents == 5_500 })
        #expect(plan.updatedTransactions.allSatisfy { $0.recurringRuleID == successor.id })
    }

    @Test("This and future leaves earlier occurrences untouched")
    func editThisAndFutureKeepsHistory() {
        let series = makeSeries()
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planEdit(
            series: series, target: target,
            scope: .thisAndFuture, edited: edited(target), calendar: calendar
        )

        let touchedIDs = Set(plan.updatedTransactions.map(\.id))
        #expect(!touchedIDs.contains(series.occurrences[0].id))
        #expect(!touchedIDs.contains(series.occurrences[1].id))
    }

    @Test("All including past rewrites every occurrence and the rule")
    func editAllIncludingPast() {
        let series = makeSeries()
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planEdit(
            series: series, target: target,
            scope: .allIncludingPast, edited: edited(target), calendar: calendar
        )

        #expect(plan.updatedTransactions.count == 5)
        #expect(plan.updatedTransactions.allSatisfy { $0.amountCents == 5_500 })
        #expect(plan.updatedRules.first?.amountCents == 5_500)
        #expect(plan.updatedRules.first?.id == series.rule.id)
        #expect(plan.updatedTransactions.map(\.date) == series.occurrences.map(\.date),
                "only the values change, never the dates")
    }

    @Test("Only the retroactive scope is flagged as rewriting history")
    func onlyRetroactiveScopeWarns() {
        #expect(SeriesScope.thisOccurrence.rewritesHistory == false)
        #expect(SeriesScope.thisAndFuture.rewritesHistory == false)
        #expect(SeriesScope.allIncludingPast.rewritesHistory)
    }

    // MARK: - Delete scopes

    @Test("Deleting this occurrence removes one row and leaves the rule alone")
    func deleteThisOccurrenceOnly() {
        let series = makeSeries()
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planDelete(
            series: series, target: target, scope: .thisOccurrence, calendar: calendar
        )

        #expect(plan.deletedTransactionIDs == [target.id])
        #expect(plan.updatedRules.isEmpty)
        #expect(plan.deletedRuleIDs.isEmpty)
    }

    @Test("Deleting this and future ends the rule and removes the tail")
    func deleteThisAndFuture() throws {
        let series = makeSeries()
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planDelete(
            series: series, target: target, scope: .thisAndFuture, calendar: calendar
        )

        #expect(plan.deletedTransactionIDs.count == 3)
        #expect(!plan.deletedTransactionIDs.contains(series.occurrences[0].id))
        let ended = try #require(plan.updatedRules.first)
        #expect(ended.isActive == false)
        #expect(try #require(ended.endDate) < target.date)
        #expect(plan.deletedRuleIDs.isEmpty, "the rule is kept so its history stays attributed")
    }

    @Test("Deleting all including past removes every occurrence and the rule")
    func deleteAllIncludingPast() {
        let series = makeSeries()

        let plan = SeriesPlanner.planDelete(
            series: series, target: series.occurrences[2],
            scope: .allIncludingPast, calendar: calendar
        )

        #expect(Set(plan.deletedTransactionIDs) == Set(series.occurrences.map(\.id)))
        #expect(plan.deletedRuleIDs == [series.rule.id])
    }

    @Test("An occurrence limit carries over proportionally when a series splits")
    func limitSplitsAcrossRules() throws {
        var rule = makeSeries().rule
        rule.occurrenceLimit = 12
        let series = RecurringSeries(rule: rule, occurrences: makeSeries().occurrences)
        let target = series.occurrences[2]

        let plan = SeriesPlanner.planEdit(
            series: series, target: target,
            scope: .thisAndFuture, edited: edited(target), calendar: calendar
        )

        let successor = try #require(plan.updatedRules.first { $0.id != rule.id })
        #expect(successor.occurrenceLimit == 10, "two already ran under the old rule")
    }
}
