import Foundation
@testable import Domain

/// Shared builders for the daily balance series suites.
///
/// Dates are UTC so a series' day boundaries never depend on the runner's locale.
enum SeriesFixtures {

    /// A UTC calendar.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Builds a UTC date.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    ///   - hour: The hour, defaulting to midday.
    /// - Returns: That instant.
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
    }

    /// Builds an account.
    /// - Parameters:
    ///   - kind: Spending account or card.
    ///   - openingCents: The opening balance.
    ///   - opened: The opening-balance date, defaulting to well before any test window.
    /// - Returns: The account.
    static func account(
        kind: AccountKind = .account,
        openingCents: Int = 0,
        opened: Date? = nil
    ) -> Account {
        Account(
            kind: kind,
            openingBalanceCents: openingCents,
            openingBalanceDate: opened ?? date(2026, 1, 1)
        )
    }

    /// Builds a transaction.
    /// - Parameters:
    ///   - type: The type.
    ///   - cents: The positive magnitude.
    ///   - account: The owning account.
    ///   - when: The date.
    /// - Returns: The transaction.
    static func entry(
        _ type: TransactionType, _ cents: Int, on account: Account, when: Date
    ) -> Transaction {
        Transaction(amountCents: cents, type: type, accountID: account.id, date: when)
    }
}
