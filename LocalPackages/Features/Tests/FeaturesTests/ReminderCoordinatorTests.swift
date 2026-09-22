import Foundation
import Testing
@testable import Features
import Domain

/// Phase 11 acceptance criteria end to end: a reminder is scheduled at the correct
/// lead time, and editing the underlying date cancels and reschedules it (§10).
@MainActor
@Suite("Reminder coordinator")
struct ReminderCoordinatorTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The product repository fake.
        let products: FakeProductRepository
        /// The authorizer fake.
        let authorizer: FakeNotificationAuthorizer
        /// The scheduler fake.
        let scheduler: FakeNotificationScheduler
        /// The coordinator under test.
        let coordinator: ReminderCoordinator
        /// The shared preferences object.
        let settings: AppSettings
    }

    /// Builds a coordinator over empty stores, with notifications already allowed.
    /// - Parameter authorized: Whether permission has been granted.
    /// - Returns: The harness.
    private func makeHarness(authorized: Bool = true) -> Harness {
        let accounts = FakeAccountRepository()
        let products = FakeProductRepository()
        let authorizer = FakeNotificationAuthorizer()
        authorizer.status = authorized ? .authorized : .denied
        let scheduler = FakeNotificationScheduler()
        return Harness(
            accounts: accounts, products: products, authorizer: authorizer, scheduler: scheduler,
            coordinator: ReminderCoordinator(
                accounts: accounts, products: products,
                authorizer: authorizer, scheduler: scheduler
            ),
            settings: AppSettings()
        )
    }

    /// A date a number of days from now, at midday.
    /// - Parameter days: Days ahead.
    /// - Returns: That date.
    private func day(_ days: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: days, to: start)?
            .addingTimeInterval(12 * 3_600) ?? .now
    }

    /// Builds a product with a trial.
    /// - Parameters:
    ///   - name: The product name.
    ///   - ends: When the trial ends.
    /// - Returns: The product.
    private func trialItem(name: String = "Streaming", ends: Date) -> Domain.Product {
        var item = Domain.Product(transactionID: UUID(), name: name)
        item.hasTrial = true
        item.trialEndsDate = ends
        item.trialReminderLeadTime = .threeDaysBefore
        return item
    }

    @Test("A trial schedules one reminder at its lead time")
    func schedulesTrialReminder() async throws {
        let harness = makeHarness()
        try await harness.products.save(trialItem(ends: day(30)))

        let scheduled = await harness.coordinator.sync(settings: harness.settings)

        #expect(scheduled.count == 1)
        let reminder = try #require(scheduled.first)
        #expect(reminder.kind == .trialEnding)
        #expect(harness.scheduler.scheduled[reminder.id] != nil)

        let expected = Calendar.current.startOfDay(for: day(27))
        #expect(Calendar.current.isDate(
            reminder.fireDate, inSameDayAs: expected
        ), "three days before the trial ends")
    }

    @Test("Editing the date cancels nothing but reschedules the same request")
    func editingDateReschedules() async throws {
        let harness = makeHarness()
        var item = trialItem(ends: day(30))
        try await harness.products.save(item)
        let first = try #require(await harness.coordinator.sync(settings: harness.settings).first)

        item.trialEndsDate = day(60)
        try await harness.products.save(item)
        let second = try #require(await harness.coordinator.sync(settings: harness.settings).first)

        #expect(second.id == first.id, "the same identifier replaces the old request")
        #expect(second.fireDate != first.fireDate)
        #expect(harness.scheduler.scheduled.count == 1, "no duplicate is left behind")
        #expect(harness.scheduler.scheduled[first.id]?.fireDate == second.fireDate)
    }

    @Test("Turning the trial off cancels its reminder")
    func disablingTrialCancels() async throws {
        let harness = makeHarness()
        var item = trialItem(ends: day(30))
        try await harness.products.save(item)
        let reminder = try #require(
            await harness.coordinator.sync(settings: harness.settings).first
        )

        item.hasTrial = false
        try await harness.products.save(item)
        let after = await harness.coordinator.sync(settings: harness.settings)

        #expect(after.isEmpty)
        #expect(harness.scheduler.scheduled.isEmpty)
        let wasCancelled = harness.scheduler.cancelled.contains { $0.contains(reminder.id) }
        #expect(wasCancelled)
    }

    @Test("Deleting a product cancels its reminder")
    func deletingProductCancels() async throws {
        let harness = makeHarness()
        let item = trialItem(ends: day(30))
        try await harness.products.save(item)
        _ = await harness.coordinator.sync(settings: harness.settings)

        try await harness.products.delete(id: item.id)
        let after = await harness.coordinator.sync(settings: harness.settings)

        #expect(after.isEmpty)
        #expect(harness.scheduler.scheduled.isEmpty)
    }

    @Test("Changing the default lead time reschedules a use-default reminder")
    func changingDefaultLeadReschedules() async throws {
        let harness = makeHarness()
        var item = trialItem(ends: day(30))
        item.trialReminderLeadTime = .useDefault
        try await harness.products.save(item)
        harness.settings.defaultReminderLeadTime = .threeDaysBefore
        let first = try #require(await harness.coordinator.sync(settings: harness.settings).first)

        harness.settings.defaultReminderLeadTime = .oneWeekBefore
        let second = try #require(await harness.coordinator.sync(settings: harness.settings).first)

        #expect(second.id == first.id)
        #expect(second.fireDate < first.fireDate, "a longer lead fires earlier")
    }

    @Test("Syncing twice with no change leaves the same reminders in place")
    func syncIsIdempotent() async throws {
        let harness = makeHarness()
        try await harness.products.save(trialItem(ends: day(30)))
        let first = await harness.coordinator.sync(settings: harness.settings)

        let second = await harness.coordinator.sync(settings: harness.settings)

        let cancelledNothing = harness.scheduler.cancelled.allSatisfy(\.isEmpty)
        #expect(second.map(\.id) == first.map(\.id))
        #expect(harness.scheduler.scheduled.count == 1)
        #expect(cancelledNothing)
    }

    @Test("Nothing is scheduled when permission was never granted")
    func unauthorizedSchedulesNothing() async throws {
        let harness = makeHarness(authorized: false)
        try await harness.products.save(trialItem(ends: day(30)))

        let scheduled = await harness.coordinator.sync(settings: harness.settings)

        #expect(scheduled.isEmpty)
        #expect(harness.scheduler.scheduled.isEmpty)
    }

    @Test("Reminders scheduled by anything else are never cancelled")
    func foreignRemindersAreLeftAlone() async throws {
        let harness = makeHarness()
        harness.scheduler.scheduled["someone.elses.reminder"] = ReminderRequest(
            id: "someone.elses.reminder", kind: .trialEnding,
            title: "Other", body: "Other", fireDate: day(5)
        )
        try await harness.products.save(trialItem(ends: day(30)))

        _ = await harness.coordinator.sync(settings: harness.settings)

        #expect(harness.scheduler.scheduled["someone.elses.reminder"] != nil)
    }

    @Test("A card schedules payment reminders at the fixed three-day lead")
    func cardPaymentReminders() async throws {
        let harness = makeHarness()
        let dueDay = Calendar.current.component(.day, from: day(20))
        try await harness.accounts.save(Domain.Account(
            name: "TD Visa", kind: .card,
            statementDayOfMonth: 5, paymentDueDayOfMonth: dueDay
        ))

        let scheduled = await harness.coordinator.sync(settings: harness.settings)

        let allArePaymentReminders = scheduled.allSatisfy { $0.kind == .cardPaymentDue }
        #expect(scheduled.count == ReminderPlanner.cardMonthsAhead)
        #expect(allArePaymentReminders)
    }

    @Test("Closing a card cancels its payment reminders")
    func closingCardCancels() async throws {
        let harness = makeHarness()
        let dueDay = Calendar.current.component(.day, from: day(20))
        var card = Domain.Account(
            name: "TD Visa", kind: .card,
            statementDayOfMonth: 5, paymentDueDayOfMonth: dueDay
        )
        try await harness.accounts.save(card)
        _ = await harness.coordinator.sync(settings: harness.settings)
        #expect(!harness.scheduler.scheduled.isEmpty)

        card.isClosed = true
        try await harness.accounts.save(card)
        let after = await harness.coordinator.sync(settings: harness.settings)

        #expect(after.isEmpty)
        #expect(harness.scheduler.scheduled.isEmpty)
    }
}
