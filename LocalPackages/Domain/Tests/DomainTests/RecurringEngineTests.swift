import Foundation
import Testing
@testable import Domain

/// Phase 6 acceptance criteria for lazy generation and catch-up (§4.5).
@Suite("Recurring engine")
struct RecurringEngineTests {

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

    /// Builds a monthly rule.
    /// - Parameters:
    ///   - start: The first occurrence.
    ///   - endDate: An optional end date.
    ///   - limit: An optional occurrence cap.
    ///   - generated: How many occurrences the cursor says exist.
    /// - Returns: The rule.
    private func monthlyRule(
        start: Date,
        endDate: Date? = nil,
        limit: Int? = nil,
        generated: Int = 0
    ) -> RecurringRule {
        RecurringRule(
            name: "Rent",
            amountCents: 150_000,
            accountID: UUID(),
            frequency: .monthly,
            startDate: start,
            endDate: endDate,
            occurrenceLimit: limit,
            occurrencesGenerated: generated
        )
    }

    /// Runs a reconcile pass.
    /// - Parameters:
    ///   - rule: The rule to reconcile.
    ///   - existing: Occurrences already stored.
    ///   - now: The moment deciding what has posted.
    /// - Returns: The outcome.
    private func reconcile(
        _ rule: RecurringRule,
        existing: [Transaction] = [],
        now: Date
    ) -> ReconcileOutcome {
        RecurringEngine.reconcile(
            rules: [rule], existingTransactions: existing, now: now, calendar: calendar
        )
    }

    @Test("A fresh rule generates exactly one unposted occurrence")
    func freshRuleGeneratesOne() {
        let rule = monthlyRule(start: date(2026, 10, 1))

        let outcome = reconcile(rule, now: date(2026, 9, 12))

        #expect(outcome.newTransactions.count == 1)
        #expect(outcome.newTransactions.first?.date == date(2026, 10, 1))
        #expect(outcome.updatedRules.first?.occurrencesGenerated == 1)
    }

    @Test("A rule that already holds an unposted occurrence generates nothing")
    func idempotentWhileUnpostedExists() {
        var rule = monthlyRule(start: date(2026, 10, 1))
        rule.occurrencesGenerated = 1
        let pending = RecurringEngine.occurrence(of: rule, on: date(2026, 10, 1))

        let outcome = reconcile(rule, existing: [pending], now: date(2026, 9, 12))

        #expect(outcome.isEmpty)
    }

    @Test("Exactly one unposted occurrence exists after repeated passes")
    func exactlyOneUnpostedInvariant() {
        var rule = monthlyRule(start: date(2026, 1, 15))
        var stored: [Transaction] = []
        let now = date(2026, 9, 12)

        for _ in 0..<3 {
            let outcome = reconcile(rule, existing: stored, now: now)
            stored.append(contentsOf: outcome.newTransactions)
            if let updated = outcome.updatedRules.first { rule = updated }
        }

        let unposted = stored.filter { $0.date > now }
        #expect(unposted.count == 1)
        #expect(unposted.first?.date == date(2026, 9, 15), "the first occurrence after 12 September")
        #expect(stored.count == 9, "January through September, generated once and not repeated")
    }

    @Test("A two-month gap generates both missed occurrences in order, then the next future one")
    func catchUpAfterTwoMonthGap() {
        // Last opened in July; two monthly charges were missed.
        var rule = monthlyRule(start: date(2026, 6, 10), generated: 2)
        rule.occurrencesGenerated = 2

        let outcome = reconcile(rule, now: date(2026, 9, 12))
        let dates = outcome.newTransactions.map(\.date)

        #expect(dates == [date(2026, 8, 10), date(2026, 9, 10), date(2026, 10, 10)])
        #expect(dates == dates.sorted(), "missed occurrences must arrive in date order")
        #expect(dates.filter { $0 > date(2026, 9, 12) }.count == 1)
        #expect(outcome.updatedRules.first?.occurrencesGenerated == 5)
    }

    @Test("Catch-up across a month-end anchor still clamps correctly")
    func catchUpPreservesClamping() {
        let rule = monthlyRule(start: date(2025, 12, 31))

        let outcome = reconcile(rule, now: date(2026, 3, 15))

        #expect(outcome.newTransactions.map(\.date) == [
            date(2025, 12, 31), date(2026, 1, 31), date(2026, 2, 28),
            date(2026, 3, 31)
        ])
    }

    @Test("Posting is silent: generated occurrences carry no state flag")
    func postingIsImplicit() {
        let rule = monthlyRule(start: date(2026, 8, 10))

        let outcome = reconcile(rule, now: date(2026, 9, 12))
        let posted = outcome.newTransactions.filter { $0.date <= date(2026, 9, 12) }

        #expect(!posted.isEmpty)
        #expect(posted.allSatisfy { $0.isSeriesOverride == false })
        #expect(posted.allSatisfy { $0.recurringRuleID == rule.id })
    }

    @Test("An end date deactivates the rule once passed")
    func endDateDeactivates() {
        let rule = monthlyRule(start: date(2026, 1, 15), endDate: date(2026, 3, 20))

        let outcome = reconcile(rule, now: date(2026, 9, 12))

        #expect(outcome.newTransactions.map(\.date) == [
            date(2026, 1, 15), date(2026, 2, 15), date(2026, 3, 15)
        ])
        #expect(outcome.updatedRules.first?.isActive == false)
    }

    @Test("An occurrence limit deactivates the rule once reached")
    func occurrenceLimitDeactivates() {
        let rule = monthlyRule(start: date(2026, 1, 15), limit: 2)

        let outcome = reconcile(rule, now: date(2026, 9, 12))

        #expect(outcome.newTransactions.count == 2)
        #expect(outcome.updatedRules.first?.isActive == false)
        #expect(outcome.updatedRules.first?.occurrencesGenerated == 2)
    }

    @Test("An already-exhausted rule deactivates without generating anything")
    func exhaustedRuleStops() {
        let rule = monthlyRule(start: date(2026, 1, 15), limit: 2, generated: 2)

        let outcome = reconcile(rule, now: date(2026, 9, 12))

        #expect(outcome.newTransactions.isEmpty)
        #expect(outcome.updatedRules.first?.isActive == false)
    }

    @Test("An inactive rule is left alone")
    func inactiveRuleIsSkipped() {
        var rule = monthlyRule(start: date(2026, 1, 15))
        rule.isActive = false

        #expect(reconcile(rule, now: date(2026, 9, 12)).isEmpty)
    }

    @Test("Deleting the pending occurrence does not resurrect it")
    func deletedOccurrenceIsNotRegenerated() throws {
        var rule = monthlyRule(start: date(2026, 1, 15))
        let first = reconcile(rule, now: date(2026, 2, 20))
        var stored = first.newTransactions
        if let updated = first.updatedRules.first { rule = updated }
        let pending = try #require(stored.first { $0.date > date(2026, 2, 20) })
        stored.removeAll { $0.id == pending.id }

        let outcome = reconcile(rule, existing: stored, now: date(2026, 2, 20))

        #expect(!outcome.newTransactions.contains { $0.date == date(2026, 3, 15) },
                "the cursor already passed this date")
    }

    @Test("A long-dormant rule stops at the catch-up cap rather than running away")
    func catchUpIsCapped() {
        let weekly = RecurringRule(
            name: "Coffee", amountCents: 500, frequency: .weekly, startDate: date(1990, 1, 1)
        )

        let outcome = reconcile(weekly, now: date(2026, 9, 12))

        #expect(outcome.newTransactions.count == RecurringEngine.catchUpLimit)
        #expect(outcome.updatedRules.first?.isActive == true, "it resumes on the next pass")
    }

    @Test("Several rules reconcile together, newest occurrences ordered by date")
    func multipleRules() {
        let rent = monthlyRule(start: date(2026, 8, 1))
        let phone = monthlyRule(start: date(2026, 8, 20))

        let outcome = RecurringEngine.reconcile(
            rules: [rent, phone], existingTransactions: [],
            now: date(2026, 9, 12), calendar: calendar
        )

        #expect(outcome.updatedRules.count == 2)
        #expect(outcome.newTransactions.map(\.date) == outcome.newTransactions.map(\.date).sorted())
    }
}
