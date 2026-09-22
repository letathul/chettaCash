import Foundation
import Testing
@testable import Domain

/// Phase 11 acceptance criteria: reminders land at the correct lead time (§10).
@Suite("Reminder planning")
struct ReminderPlannerTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test plans against.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 8)) ?? .now
    }

    /// Builds a UTC date at the reminder fire hour.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    /// - Returns: That day at 09:00.
    private func fireDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: ReminderPlanner.fireHour
        )) ?? .now
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

    /// Plans reminders.
    /// - Parameters:
    ///   - accounts: Accounts to plan for.
    ///   - items: Products to plan for.
    ///   - defaultLead: The fallback lead time.
    /// - Returns: The reminders.
    private func plan(
        accounts: [Account] = [],
        items: [Product] = [],
        defaultLead: ReminderLeadTime = .threeDaysBefore
    ) -> [ReminderRequest] {
        ReminderPlanner.reminders(
            from: ReminderInput(
                accounts: accounts, products: items, defaultLeadTime: defaultLead
            ),
            now: now,
            calendar: calendar
        )
    }

    /// Builds a product with a trial.
    /// - Parameters:
    ///   - ends: When the trial ends.
    ///   - lead: The trial's lead time.
    /// - Returns: The product.
    private func trialItem(ends: Date, lead: ReminderLeadTime) -> Product {
        var item = Product(transactionID: UUID(), name: "Streaming")
        item.hasTrial = true
        item.trialEndsDate = ends
        item.trialReminderLeadTime = lead
        return item
    }

    // MARK: - Lead times (§10)

    @Test("A trial reminder fires exactly its lead time before the end date", arguments: [
        (ReminderLeadTime.sameDay, 30),
        (ReminderLeadTime.oneDayBefore, 29),
        (ReminderLeadTime.threeDaysBefore, 27),
        (ReminderLeadTime.oneWeekBefore, 23)
    ])
    func trialLeadTimes(lead: ReminderLeadTime, expectedDay: Int) throws {
        let item = trialItem(ends: date(2026, 9, 30), lead: lead)

        let reminder = try #require(plan(items: [item]).first)

        #expect(reminder.kind == .trialEnding)
        #expect(reminder.fireDate == fireDate(2026, 9, expectedDay))
    }

    @Test("A lead time of off schedules nothing")
    func offSchedulesNothing() {
        #expect(plan(items: [trialItem(ends: date(2026, 9, 30), lead: .off)]).isEmpty)
    }

    @Test("Use default falls back to the app's default lead time")
    func useDefaultFallsBack() throws {
        let item = trialItem(ends: date(2026, 9, 30), lead: .useDefault)

        let weekly = try #require(plan(items: [item], defaultLead: .oneWeekBefore).first)
        let daily = try #require(plan(items: [item], defaultLead: .oneDayBefore).first)

        #expect(weekly.fireDate == fireDate(2026, 9, 23))
        #expect(daily.fireDate == fireDate(2026, 9, 29))
    }

    @Test("A reminder whose fire date has already passed is not scheduled")
    func pastReminderIsSkipped() {
        let item = trialItem(ends: date(2026, 9, 13), lead: .oneWeekBefore)
        #expect(plan(items: [item]).isEmpty, "the fire date was 6 September")
    }

    @Test("A warranty reminder uses its own lead time")
    func warrantyLeadTime() throws {
        var item = Product(transactionID: UUID(), name: "Laptop")
        item.hasWarranty = true
        item.warrantyExpiresDate = date(2026, 10, 20)
        item.warrantyReminderLeadTime = .oneWeekBefore

        let reminder = try #require(plan(items: [item]).first)

        #expect(reminder.kind == .warrantyExpiring)
        #expect(reminder.fireDate == fireDate(2026, 10, 13))
    }

    @Test("A product with both dates gets two reminders with distinct identifiers")
    func trialAndWarrantyBothScheduled() {
        var item = trialItem(ends: date(2026, 9, 30), lead: .threeDaysBefore)
        item.hasWarranty = true
        item.warrantyExpiresDate = date(2026, 10, 20)
        item.warrantyReminderLeadTime = .threeDaysBefore

        let reminders = plan(items: [item])

        #expect(reminders.count == 2)
        #expect(Set(reminders.map(\.id)).count == 2)
    }

    @Test("A toggle switched off removes that reminder from the plan")
    func toggleOffRemovesReminder() {
        var item = trialItem(ends: date(2026, 9, 30), lead: .threeDaysBefore)
        item.hasTrial = false

        #expect(plan(items: [item]).isEmpty)
    }

    // MARK: - Card payments (§10)

    /// Builds a card with a payment due day.
    /// - Parameters:
    ///   - dueDay: The day of month payment is due.
    ///   - reminds: Whether reminders are on.
    /// - Returns: The card.
    private func card(dueDay: Int, reminds: Bool = true) -> Account {
        Account(
            name: "TD Visa", kind: .card,
            statementDayOfMonth: 5, paymentDueDayOfMonth: dueDay,
            remindBeforeDueDate: reminds
        )
    }

    @Test("A card reminder uses the fixed three-day lead, not the default")
    func cardUsesFixedLead() throws {
        let reminders = plan(accounts: [card(dueDay: 25)], defaultLead: .oneWeekBefore)

        let first = try #require(reminders.first)
        #expect(first.kind == .cardPaymentDue)
        #expect(first.fireDate == fireDate(2026, 9, 22), "three days before the 25th")
    }

    @Test("Several months of card reminders are scheduled ahead")
    func cardSchedulesMonthsAhead() {
        let reminders = plan(accounts: [card(dueDay: 25)])

        #expect(reminders.count == ReminderPlanner.cardMonthsAhead)
        #expect(reminders.map(\.fireDate) == [
            fireDate(2026, 9, 22), fireDate(2026, 10, 22), fireDate(2026, 11, 22)
        ])
        #expect(Set(reminders.map(\.id)).count == ReminderPlanner.cardMonthsAhead)
    }

    @Test("A due day early in the month reminds in the previous month")
    func earlyDueDayRemindsInPreviousMonth() throws {
        let reminders = plan(accounts: [card(dueDay: 2)])

        let first = try #require(reminders.first)
        #expect(first.fireDate == fireDate(2026, 9, 29), "three days before 2 October")
    }

    @Test("A card with reminders switched off schedules nothing")
    func cardRemindersOff() {
        #expect(plan(accounts: [card(dueDay: 25, reminds: false)]).isEmpty)
    }

    @Test("A closed card schedules nothing")
    func closedCardSchedulesNothing() {
        var closed = card(dueDay: 25)
        closed.isClosed = true
        #expect(plan(accounts: [closed]).isEmpty)
    }

    @Test("A spending account never gets payment reminders")
    func spendingAccountsAreSkipped() {
        let chequing = Account(name: "Chequing", kind: .account, paymentDueDayOfMonth: 25)
        #expect(plan(accounts: [chequing]).isEmpty)
    }

    // MARK: - Identifiers and ordering

    @Test("Every identifier carries the app's prefix, so nothing else is disturbed")
    func identifiersArePrefixed() {
        let reminders = plan(
            accounts: [card(dueDay: 25)],
            items: [trialItem(ends: date(2026, 9, 30), lead: .threeDaysBefore)]
        )

        #expect(!reminders.isEmpty)
        #expect(reminders.allSatisfy { $0.id.hasPrefix(ReminderPlanner.identifierPrefix) })
    }

    @Test("An identifier is stable across replans, so a date change replaces it")
    func identifiersAreStable() throws {
        var item = trialItem(ends: date(2026, 9, 30), lead: .threeDaysBefore)
        let before = try #require(plan(items: [item]).first)

        item.trialEndsDate = date(2026, 10, 15)
        let after = try #require(plan(items: [item]).first)

        #expect(after.id == before.id, "the same request is replaced, not duplicated")
        #expect(after.fireDate != before.fireDate)
    }

    @Test("Reminders come back soonest first")
    func remindersAreOrdered() {
        let reminders = plan(
            accounts: [card(dueDay: 25)],
            items: [trialItem(ends: date(2026, 9, 18), lead: .threeDaysBefore)]
        )

        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
    }

    @Test("Reminders fire mid-morning rather than at midnight")
    func remindersFireAtNineLocal() throws {
        let reminder = try #require(
            plan(items: [trialItem(ends: date(2026, 9, 30), lead: .threeDaysBefore)]).first
        )

        #expect(calendar.component(.hour, from: reminder.fireDate) == ReminderPlanner.fireHour)
    }
}
