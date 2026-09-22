import Foundation
import Testing
@testable import Domain

/// Phase 8 acceptance criteria continued: the Today sheet's upcoming and
/// ending-soon sections (§7.2).
@Suite("Today upcoming and ending soon")
struct TodayHorizonTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test evaluates against.
    ///
    /// Evening, so a transaction dated midday today has already posted.
    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 18
        )) ?? .now
    }

    /// A date offset from ``now`` by whole days.
    /// - Parameter days: Days to offset.
    /// - Returns: The offset date, at midday.
    private func day(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))?
            .addingTimeInterval(12 * 3_600) ?? now
    }

    /// A spending account.
    private var chequing: Account {
        Account(name: "Chequing", openingBalanceCents: 100_000,
                openingBalanceDate: day(-200))
    }

    /// Builds a digest.
    /// - Parameter input: The inputs to build from.
    /// - Returns: The digest.
    private func digest(_ input: TodayInput) -> TodayDigest {
        TodayBuilder.digest(from: input, now: now, calendar: calendar)
    }

    // MARK: - Upcoming charges

    @Test("The next occurrence per rule is listed, soonest first")
    func upcomingChargesListed() {
        let account = chequing
        let rent = RecurringRule(
            name: "Rent", amountCents: 180_000, accountID: account.id, startDate: day(-30)
        )
        let phone = RecurringRule(
            name: "Phone", amountCents: 4_500, accountID: account.id, startDate: day(-20)
        )
        let occurrences = [
            RecurringEngine.occurrence(of: rent, on: day(8)),
            RecurringEngine.occurrence(of: rent, on: day(38)),
            RecurringEngine.occurrence(of: phone, on: day(3))
        ]

        let result = digest(TodayInput(
            accounts: [account], transactions: occurrences, rules: [rent, phone]
        ))

        #expect(result.upcomingCharges.count == 2, "one per rule, not one per occurrence")
        #expect(result.upcomingCharges.map(\.rule.name) == ["Phone", "Rent"])
    }

    @Test("A charge beyond thirty days is out of horizon")
    func chargeBeyondHorizon() {
        let account = chequing
        let rule = RecurringRule(
            name: "Yearly", amountCents: 9_900, accountID: account.id,
            frequency: .yearly, startDate: day(-330)
        )
        let occurrence = RecurringEngine.occurrence(of: rule, on: day(35))

        let result = digest(TodayInput(
            accounts: [account], transactions: [occurrence], rules: [rule]
        ))

        #expect(result.upcomingCharges.isEmpty)
    }

    @Test("An inactive rule contributes nothing")
    func inactiveRuleIsSkipped() {
        let account = chequing
        var rule = RecurringRule(name: "Gone", accountID: account.id, startDate: day(-30))
        rule.isActive = false
        let occurrence = RecurringEngine.occurrence(of: rule, on: day(5))

        let result = digest(TodayInput(
            accounts: [account], transactions: [occurrence], rules: [rule]
        ))

        #expect(result.upcomingCharges.isEmpty)
    }

    // MARK: - Ending soon

    @Test("A trial inside its lead window is listed")
    func trialEndingSoon() throws {
        var item = Product(transactionID: UUID(), name: "Streaming")
        item.hasTrial = true
        item.trialEndsDate = day(2)
        item.trialReminderLeadTime = .threeDaysBefore

        let result = digest(TodayInput(products: [item]))

        let ending = try #require(result.endingSoon.first)
        #expect(ending.kind == .trial)
        #expect(ending.daysRemaining == 2)
    }

    @Test("A trial beyond its lead window is not listed")
    func trialOutsideWindow() {
        var item = Product(transactionID: UUID(), name: "Streaming")
        item.hasTrial = true
        item.trialEndsDate = day(10)
        item.trialReminderLeadTime = .threeDaysBefore

        #expect(digest(TodayInput(products: [item])).endingSoon.isEmpty)
    }

    @Test("Use-default falls back to the app's default lead time")
    func useDefaultFallsBack() {
        var item = Product(transactionID: UUID(), name: "Streaming")
        item.hasTrial = true
        item.trialEndsDate = day(6)
        item.trialReminderLeadTime = .useDefault

        let narrow = digest(TodayInput(products: [item], defaultLeadTime: .threeDaysBefore))
        let wide = digest(TodayInput(products: [item], defaultLeadTime: .oneWeekBefore))

        #expect(narrow.endingSoon.isEmpty)
        #expect(wide.endingSoon.count == 1)
    }

    @Test("A reminder switched off is never listed")
    func reminderOffIsSkipped() {
        var item = Product(transactionID: UUID(), name: "Streaming")
        item.hasTrial = true
        item.trialEndsDate = day(1)
        item.trialReminderLeadTime = .off

        #expect(digest(TodayInput(products: [item])).endingSoon.isEmpty)
    }

    @Test("A product with both a trial and a warranty can appear twice")
    func trialAndWarrantyBothListed() {
        var item = Product(transactionID: UUID(), name: "Laptop")
        item.hasTrial = true
        item.trialEndsDate = day(1)
        item.trialReminderLeadTime = .threeDaysBefore
        item.hasWarranty = true
        item.warrantyExpiresDate = day(2)
        item.warrantyReminderLeadTime = .threeDaysBefore

        let result = digest(TodayInput(products: [item]))

        #expect(result.endingSoon.count == 2)
        #expect(Set(result.endingSoon.map(\.id)).count == 2, "identities must not collide")
    }
}
