import Foundation
import Testing
@testable import Domain

/// Recognising a Shortcut run that has already happened (§15.6).
///
/// The guard is deliberately narrow, so most of these pin down what it must *not* catch.
/// Suppressing a real second purchase is the worse failure: a duplicate is visible in the
/// Ledger and can be deleted, where a suppressed purchase is money that never appears.
@Suite("Quick expense duplicate guard")
struct QuickExpenseDuplicateGuardTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The account every entry here belongs to.
    private var accountID: UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID() }

    /// Midday, so a two-minute window never crosses a day boundary by accident.
    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)) ?? .now
    }

    /// An entry as a Shortcut writes one.
    /// - Parameters:
    ///   - merchant: The merchant.
    ///   - cents: The amount in cents.
    ///   - date: When it happened.
    ///   - account: The account it belongs to. Defaults to ``accountID``.
    ///   - isParked: Whether it has no account at all, as a Shortcut parks one.
    ///   - tags: The tags it carries.
    /// - Returns: The transaction.
    private func shortcutEntry(
        merchant: String = "Whole Foods",
        cents: Int = 4_210,
        date: Date? = nil,
        account: UUID? = nil,
        isParked: Bool = false,
        tags: [String] = [QuickExpensePlanner.originTag]
    ) -> Transaction {
        Transaction(
            amountCents: cents,
            type: .expense,
            accountID: isParked ? nil : (account ?? accountID),
            date: date ?? noon,
            merchant: merchant,
            tags: tags
        )
    }

    /// Runs the guard with the fixed calendar.
    /// - Parameters:
    ///   - candidate: The entry about to be written.
    ///   - stored: The entries already stored.
    /// - Returns: The duplicate, if any.
    private func duplicate(_ candidate: Transaction, among stored: [Transaction]) -> Transaction? {
        QuickExpenseDuplicateGuard.duplicate(of: candidate, among: stored, calendar: calendar)
    }

    // MARK: - What it catches

    @Test("The same entry seconds later is the same run, repeated")
    func catchesARetry() {
        let first = shortcutEntry()
        let retry = shortcutEntry(date: noon.addingTimeInterval(8))

        #expect(duplicate(retry, among: [first])?.id == first.id)
    }

    @Test("An automation passing the same timestamp matches exactly")
    func catchesAnIdenticalTimestamp() {
        let first = shortcutEntry()

        #expect(duplicate(shortcutEntry(), among: [first])?.id == first.id)
    }

    @Test("A merchant spelt differently is still the same shop")
    func catchesADifferentSpelling() {
        let first = shortcutEntry(merchant: "WHOLE FOODS MKT #10234")
        let retry = shortcutEntry(merchant: "Whole Foods Mkt", date: noon.addingTimeInterval(5))

        #expect(
            duplicate(retry, among: [first])?.id == first.id,
            "the fingerprint normalises the merchant, branch number and all"
        )
    }

    // MARK: - What it must not catch

    @Test("Two identical coffees hours apart are two coffees")
    func allowsARealSecondPurchase() {
        let morning = shortcutEntry(merchant: "Blue Bottle", cents: 450)
        let afternoon = shortcutEntry(
            merchant: "Blue Bottle", cents: 450, date: noon.addingTimeInterval(4 * 3_600)
        )

        #expect(duplicate(afternoon, among: [morning]) == nil)
    }

    @Test("A twin the user typed in by hand is never suppressed")
    func allowsAManualTwin() {
        let typed = shortcutEntry(tags: [])
        let shortcut = shortcutEntry(date: noon.addingTimeInterval(10))

        #expect(
            duplicate(shortcut, among: [typed]) == nil,
            "they meant that one, and they were watching when they entered it"
        )
    }

    @Test("A different amount is a different purchase", arguments: [4_209, 4_211, 0])
    func allowsADifferentAmount(_ cents: Int) {
        let first = shortcutEntry()

        let other = shortcutEntry(cents: cents, date: noon.addingTimeInterval(5))

        #expect(duplicate(other, among: [first]) == nil)
    }

    @Test("A different merchant is a different purchase")
    func allowsADifferentMerchant() {
        let first = shortcutEntry()

        #expect(duplicate(shortcutEntry(merchant: "Blue Bottle"), among: [first]) == nil)
    }

    @Test("The same purchase on another card is another purchase")
    func allowsADifferentAccount() {
        let first = shortcutEntry()

        #expect(duplicate(shortcutEntry(account: UUID()), among: [first]) == nil)
    }

    @Test("An entry never counts as its own duplicate")
    func allowsTheSameRow() {
        let stored = shortcutEntry()

        #expect(
            duplicate(stored, among: [stored]) == nil,
            "editing an entry through the same path must not refuse to save it"
        )
    }

    @Test("Two parked entries that match are still one run repeated")
    func catchesAParkedRetry() {
        let first = shortcutEntry(isParked: true)
        let retry = shortcutEntry(date: noon.addingTimeInterval(5), isParked: true)

        #expect(duplicate(retry, among: [first])?.id == first.id)
    }

    // MARK: - The day it searches

    @Test("The search range covers the candidate's own day and no more")
    func searchesOneDay() throws {
        let range = try #require(
            QuickExpenseDuplicateGuard.searchRange(for: shortcutEntry(), calendar: calendar)
        )

        #expect(range.contains(noon))
        #expect(range.contains(calendar.startOfDay(for: noon)))
        #expect(range.contains(noon.addingTimeInterval(24 * 3_600)) == false)
    }
}
