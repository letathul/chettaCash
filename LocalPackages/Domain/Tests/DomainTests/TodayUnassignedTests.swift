import Foundation
import Testing
@testable import Domain

/// The Today section for entries a Shortcut could not file (§15.5, §7.2).
///
/// A parked entry is the one thing in the digest the user has to act on before the app's
/// own figures agree with each other: it counts toward spend and moves no balance, so
/// Spend and Available Cash differ by exactly this much until it is assigned.
@Suite("Today unassigned entries")
struct TodayUnassignedTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test evaluates against.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 18)) ?? .now
    }

    /// A date offset from ``now`` by whole days, at midday.
    /// - Parameter days: Days to offset.
    /// - Returns: The offset date.
    private func day(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))?
            .addingTimeInterval(12 * 3_600) ?? now
    }

    /// Builds a digest from transactions alone.
    /// - Parameters:
    ///   - transactions: The transactions to build from.
    ///   - accounts: The accounts to build from.
    /// - Returns: The digest.
    private func digest(
        _ transactions: [Transaction],
        accounts: [Account] = []
    ) -> TodayDigest {
        TodayBuilder.digest(
            from: TodayInput(accounts: accounts, transactions: transactions),
            now: now,
            calendar: calendar
        )
    }

    /// An expense with no account, as a Shortcut parks one.
    /// - Parameters:
    ///   - merchant: The merchant.
    ///   - date: When it happened.
    /// - Returns: The transaction.
    private func parked(_ merchant: String, on date: Date) -> Transaction {
        Transaction(
            amountCents: 4_210, type: .expense, accountID: nil, date: date, merchant: merchant
        )
    }

    @Test("An entry with no account is surfaced")
    func surfacesAParkedEntry() throws {
        let result = digest([parked("Whole Foods", on: day(0))])

        let item = try #require(result.unassignedEntries.first)
        #expect(result.unassignedEntries.count == 1)
        #expect(item.merchant == "Whole Foods")
        #expect(item.amountCents == 4_210)
    }

    @Test("An entry that has an account is not surfaced")
    func ignoresAFiledEntry() {
        let account = Account(name: "Chequing", openingBalanceDate: day(-200))
        let filed = Transaction(
            amountCents: 4_210, type: .expense, accountID: account.id,
            date: day(0), merchant: "Whole Foods"
        )

        let result = digest([filed], accounts: [account])

        #expect(result.unassignedEntries.isEmpty)
    }

    @Test("Parked entries are listed newest first")
    func ordersNewestFirst() {
        let result = digest([
            parked("Older", on: day(-3)),
            parked("Newest", on: day(-1)),
            parked("Middle", on: day(-2))
        ])

        #expect(result.unassignedEntries.map(\.merchant) == ["Newest", "Middle", "Older"])
    }

    @Test("A future-dated parked entry is surfaced too")
    func surfacesAFutureParkedEntry() {
        let result = digest([parked("Whole Foods", on: day(7))])

        #expect(
            result.unassignedEntries.count == 1,
            "waiting for its date would hide it for exactly as long as it is easiest to fix"
        )
    }

    @Test("A day with a parked entry is not a quiet day")
    func aParkedEntryBreaksTheQuiet() {
        let result = digest([parked("Whole Foods", on: day(-5))])

        #expect(result.spentTodayCents == 0, "nothing was spent today")
        #expect(result.isQuietDay == false, "but something still needs the user")
    }
}
